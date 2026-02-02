package sidewinder;

import sys.db.Connection;
import sys.db.Sqlite;
import sys.thread.Mutex;
import DateTools;
import sidewinder.IDatabaseService;

/**
 * SQLite implementation of the database service
 */
class SqliteDatabaseService implements IDatabaseService {

	static inline var DB_PATH = "data.db";
	static inline var MAX_POOL_SIZE = 8;

	var mutex = new Mutex();
	var pool:Array<Connection> = [];

	public function new() {}

	public function acquire():Connection {
		mutex.acquire();
		var conn = pool.pop();
		mutex.release();

		if (conn != null)
			return conn;

		var c = Sqlite.open(DB_PATH);
		c.request("PRAGMA foreign_keys = ON;");
		c.request("PRAGMA journal_mode = WAL;");

		return c;
	}

	function ensureMigrationsTable(conn:Connection):Void {
		conn.request('CREATE TABLE IF NOT EXISTS migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TEXT DEFAULT CURRENT_TIMESTAMP);');
	}

	function getMigrationFiles():Array<String> {
		var dir = "migrations/sqlite";
		var files = sys.FileSystem.readDirectory(dir);
		var sqlFiles = files.filter(function(f) return StringTools.endsWith(f, ".sql"));
		sqlFiles.sort(function(a, b) return Reflect.compare(a, b));
		return sqlFiles;
	}

	public function release(conn:Connection):Void {
		mutex.acquire();
		if (pool.length < MAX_POOL_SIZE)
			pool.push(conn);
		else
			conn.close();
		mutex.release();
	}

	/**
	 * Build an SQL string by substituting named parameters with their formatted values.
	 */
	public function buildSql(sql:String, params:Map<String, Dynamic>):String {
		if (params == null || params.keys().hasNext() == false) return sql;
		var out = new StringBuf();
		var i = 0;
		while (i < sql.length) {
			var ch = sql.charAt(i);
			// Handle single quoted string literal to avoid replacing inside it
			if (ch == "'") {
				out.add(ch);
				i++;
				while (i < sql.length) {
					var c2 = sql.charAt(i);
					out.add(c2);
					if (c2 == "'") {
						// Handle escaped '' inside literal
						if (i + 1 < sql.length && sql.charAt(i + 1) == "'") {
							out.add("'");
							i += 2;
							continue;
						}
						else {
							i++;
							break;
						}
					}
					i++;
				}
				continue;
			}
			// Parameter start
			if (ch == '@' || ch == ':') {
				var start = i + 1;
				while (start < sql.length && isIdentChar(sql.charCodeAt(start))) start++;
				var name = sql.substr(i + 1, start - (i + 1));
				if (name.length > 0 && params.exists(name)) {
					out.add(formatValue(params.get(name)));
					i = start;
					continue;
				}
			}
			out.add(ch);
			i++;
		}
		return out.toString();
	}

	/** Helper to determine identifier characters */
	private static inline function isIdentChar(code:Int):Bool {
		return (code >= 'A'.code && code <= 'Z'.code) || (code >= 'a'.code && code <= 'z'.code) || (code >= '0'.code && code <= '9'.code) || code == '_'.code;
	}

	/** Convenience to create RawSql */
	public inline function raw(v:String):RawSql return new RawSql(v);

	/** Formats a value for inclusion in SQL */
	private function formatValue(v:Dynamic):String {
		if (v == null) return "NULL";
		// Raw SQL passthrough
		if (Std.isOfType(v, RawSql)) return cast(v, RawSql).value;
		// Arrays -> (item1,item2,...)
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = cast v;
			var parts = [];
			for (item in arr) parts.push(formatValueScalar(item));
			return '(' + parts.join(',') + ')';
		}
		return formatValueScalar(v);
	}

	private function formatValueScalar(v:Dynamic):String {
		if (v == null) return "NULL";
		if (Std.isOfType(v, String)) return quoteString(cast v);
		if (Std.isOfType(v, Bool)) return (cast v ? '1' : '0');
		if (Std.isOfType(v, Date)) {
			var d:Date = cast v;
			var formatted = DateTools.format(d, "%Y-%m-%d %H:%M:%S");
			return quoteString(formatted);
		}
		// Int / Float
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float)) return Std.string(v);
		// Fallback: toString then quote
		return quoteString(Std.string(v));
	}

	/** Execute a request with optional named parameters, returns ResultSet */
	public function requestWithParams(sql:String, ?params:Map<String, Dynamic>):sys.db.ResultSet {
		var conn = acquire();
		var finalSql = (params != null) ? buildSql(sql, params) : sql;
		var rs = conn.request(finalSql);
		release(conn);
		return rs;
	}

	/** Execute a non-query (INSERT/UPDATE/DELETE) returning nothing */
	public function execute(sql:String, ?params:Map<String, Dynamic>):Void {
		var conn = acquire();
		var finalSql = (params != null) ? buildSql(sql, params) : sql;
		conn.request(finalSql);
		release(conn);
	}

    public function runMigrations():Void {
		var conn = acquire();
		ensureMigrationsTable(conn);
		var applied = new Map<String, Bool>();
		var rs = conn.request("SELECT name FROM migrations;");
		while (rs.hasNext()) {
            var record = rs.next();
			applied.set(record.name, true);
		}
		var dir = "migrations/sqlite";
		var files = sys.FileSystem.readDirectory(dir);
		var sqlFiles = files.filter(function(f) return StringTools.endsWith(f, ".sql"));
		sqlFiles.sort(function(a, b) return Reflect.compare(a, b));
		for (file in sqlFiles) {
			if (!applied.exists(file)) {
				var sql = sys.io.File.getContent(dir + "/" + file);
				try {
					// Split by semicolon, but keep in mind that semicolons inside strings/comments are not handled
                    var statements = sql.split(';');

                    for (stmt in statements) {
                        stmt = StringTools.trim(stmt);
                        if (stmt.length == 0) continue;
                        conn.request(stmt);
                    }

                    conn.request("INSERT INTO migrations (name) VALUES (" + quoteString(file) + ");");
                    
				} catch (e:Dynamic) {
					trace('Migration failed for ' + file + ': ' + e);
				}
			}
		}
		release(conn);
	}

    /**
     * Escapes single quotes in a string for safe SQL usage.
     */
    public function escapeString(str:String):String {
        return str == null ? null : StringTools.replace(str, "'", "''");
    }

    /**
     * Quotes a string for safe SQL usage.
     */
    public function quoteString(str:String):String {
        return str == null ? null : "'" + StringTools.replace(str, "'", "''") + "'";
    }

    /**
     * Sanitizes input by trimming and escaping single quotes.
     */
    public function sanitize(str:String):String {
        return str == null ? null : escapeString(StringTools.trim(str));
    }

}
