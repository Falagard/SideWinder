package;

import sys.db.Connection;
import sys.db.Sqlite;
import sys.thread.Mutex;

class Database {

	static inline var DB_PATH = "data.db";
	static inline var MAX_POOL_SIZE = 8;

	static var mutex = new Mutex();
	static var pool:Array<Connection> = [];

	public static function acquire():Connection {
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

	static function ensureMigrationsTable(conn:Connection):Void {
		conn.request('CREATE TABLE IF NOT EXISTS migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TEXT DEFAULT CURRENT_TIMESTAMP);');
	}

	static function getMigrationFiles():Array<String> {
		var dir = "migrations";
		var files = sys.FileSystem.readDirectory(dir);
		var sqlFiles = files.filter(function(f) return StringTools.endsWith(f, ".sql"));
		sqlFiles.sort(function(a, b) return Reflect.compare(a, b));
		return sqlFiles;
	}

	public static function release(conn:Connection):Void {
		mutex.acquire();
		if (pool.length < MAX_POOL_SIZE)
			pool.push(conn);
		else
			conn.close();
		mutex.release();
	}

    public static function runMigrations():Void {
		var conn = acquire();
		ensureMigrationsTable(conn);
		var applied = new Map<String, Bool>();
		var rs = conn.request("SELECT name FROM migrations;");
		while (rs.hasNext()) {
            var record = rs.next();
			applied.set(record.name, true);
		}
		var dir = "migrations";
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
    public static function escapeString(str:String):String {
        return str == null ? null : StringTools.replace(str, "'", "''");
    }

    /**
     * Quotes a string for safe SQL usage.
     */
    public static function quoteString(str:String):String {
        return str == null ? null : "'" + StringTools.replace(str, "'", "''") + "'";
    }

    /**
     * Sanitizes input by trimming and escaping single quotes.
     */
    public static function sanitize(str:String):String {
        return str == null ? null : escapeString(StringTools.trim(str));
    }

}
