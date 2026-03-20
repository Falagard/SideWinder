package sidewinder.services;

import sidewinder.interfaces.IDatabaseService.RawSql;
import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;
import sys.db.Connection;
import sys.db.ResultSet;
import sys.db.Sqlite;
import sys.thread.Mutex;
import sys.thread.Thread;
import sys.thread.Deque;
import haxe.ThreadLocal;
import DateTools;

/**
 * SQLite implementation of the database service.
 * Refactored for SQLite optimization:
 * - Thread-local read connections using haxe.ThreadLocal (from hxwell).
 * - Dedicated background writer thread to serialize all writes.
 */
class SqliteDatabaseService implements IDatabaseService {
	static inline var DB_PATH = "data.db";
	static inline var MAX_POOL_SIZE = 32;

	// Shared resources
	var mutex = new Mutex();
	var pool:Array<Connection> = [];

	// Thread-local storage for read connections
	var threadConn = new ThreadLocal<Connection>(() -> {
		var conn = Sqlite.open(DB_PATH);
		conn.request("PRAGMA foreign_keys = ON;");
		conn.request("PRAGMA journal_mode = WAL;");
		conn.request("PRAGMA synchronous = normal;");
		conn.request("PRAGMA temp_store = memory;");
		conn.request("PRAGMA mmap_size = 30000000000;");
		return conn;
	}, (conn) -> {
		if (conn != null)
			conn.close();
	});

	// Writer thread components
	var writeQueue = new Deque<WriteRequest>();
	var writerThread:Thread;

	public function new() {
		startWriterThread();
	}

	private function startWriterThread() {
		writerThread = Thread.create(() -> {
			while (true) {
				try {
					var conn = Sqlite.open(DB_PATH);
					conn.request("PRAGMA foreign_keys = ON;");
					conn.request("PRAGMA journal_mode = WAL;");
					conn.request("PRAGMA synchronous = normal;");
					conn.request("PRAGMA temp_store = memory;");
					conn.request("PRAGMA mmap_size = 30000000000;");

					while (true) {
						var request = writeQueue.pop(true);
						if (request == null)
							continue;

						try {
							var rs = null;
							var lastId = -1;
							var retries = 10; // More retries for high concurrency

							while (true) {
								try {
									rs = conn.request(request.sql);
									if (request.returnId) {
										var changes = conn.request("SELECT changes();").getIntResult(0);
										if (changes == 0) {
											throw "No rows affected (possible UNIQUE constraint violation)";
										}
										lastId = conn.lastInsertId();
										HybridLogger.debug('[SqliteDatabaseService] Inserted ID: ' + lastId + ' for SQL: ' + request.sql);
									}
									break;
								} catch (e:Dynamic) {
									var err = Std.string(e).toLowerCase();
									if (retries > 0 && (err.indexOf("locked") != -1 || err.indexOf("busy") != -1)) {
										retries--;
										Sys.sleep(0.01 + (10 - retries) * 0.01); // Incremental backoff
										continue;
									}
									throw e;
								}
							}
							request.response.push({rs: rs, error: null, lastId: lastId});
						} catch (e:Dynamic) {
							// Single-query error doesn't kill the thread loop
							HybridLogger.warn('[SqliteDatabaseService] Write error (query continued): ' + e);
							request.response.push({rs: null, error: e, lastId: -1});
						}
					}
				} catch (e:Dynamic) {
					// Critical error (e.g. file locked)
					HybridLogger.error("Fatal error in SQLite writer thread (restarting in 1s): " + e);
					Sys.sleep(1.0);
				}
			}
		});
	}

	public function acquire():Connection {
		return threadConn.get();
	}

	public function release(conn:Connection):Void {
		// Handled by ThreadLocal
	}

	public function requestRead(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		var conn = acquire();
		var finalSql = (params != null) ? buildSql(sql, params) : sql;
		var retries = 5;
		while (true) {
			try {
				return conn.request(finalSql);
			} catch (e:Dynamic) {
				var err = Std.string(e).toLowerCase();
				if (retries > 0 && (err.indexOf("locked") != -1 || err.indexOf("busy") != -1)) {
					retries--;
					Sys.sleep(0.01);
					continue;
				}
				throw e;
			}
		}
	}

	public inline function read(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		return requestRead(sql, params);
	}

	public function requestWrite(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		var finalSql = (params != null) ? buildSql(sql, params) : sql;
		var responseQueue = new Deque<WriteResponse>();

		writeQueue.push({
			sql: finalSql,
			response: responseQueue,
			returnId: false
		});

		var res = responseQueue.pop(true);
		if (res.error != null) {
			throw res.error;
		}
		return res.rs;
	}

	public inline function write(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		return requestWrite(sql, params);
	}

	public function executeAndGetId(sql:String, ?params:Map<String, Dynamic>):Int {
		var finalSql = (params != null) ? buildSql(sql, params) : sql;
		var responseQueue = new Deque<WriteResponse>();

		writeQueue.push({
			sql: finalSql,
			response: responseQueue,
			returnId: true
		});

		var res = responseQueue.pop(true);
		if (res.error != null) {
			throw res.error;
		}
		HybridLogger.debug('[SqliteDatabaseService] Returning ID: ' + res.lastId);
		return res.lastId;
	}

	public function requestWithParams(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		var trimmed = StringTools.trim(sql).toUpperCase();
		if (StringTools.startsWith(trimmed, "SELECT") || StringTools.startsWith(trimmed, "PRAGMA")) {
			return requestRead(sql, params);
		} else {
			return requestWrite(sql, params);
		}
	}

	public function execute(sql:String, ?params:Map<String, Dynamic>):Void {
		requestWrite(sql, params);
	}

	public function runMigrations():Void {
		var dir = "migrations/sqlite";
		trace("SqliteDatabaseService.runMigrations() dir: " + dir + " cwd: " + sys.FileSystem.fullPath("."));

		trace("SqliteDatabaseService.runMigrations() Creating migrations table if not exists...");
		execute('CREATE TABLE IF NOT EXISTS migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TEXT DEFAULT CURRENT_TIMESTAMP);');

		var rs = requestRead("SELECT name FROM migrations;");
		var applied = new Map<String, Bool>();
		while (rs.hasNext()) {
			applied.set(rs.next().name, true);
		}

		if (!sys.FileSystem.exists(dir)) {
			trace("SqliteDatabaseService.runMigrations() dir NOT FOUND: " + dir);
			return;
		}

		var files = sys.FileSystem.readDirectory(dir);
		trace("SqliteDatabaseService.runMigrations() found files: " + files.length);
		var sqlFiles = files.filter(f -> StringTools.endsWith(f, ".sql"));
		trace("SqliteDatabaseService.runMigrations() sql files: " + sqlFiles.length);
		sqlFiles.sort((a, b) -> Reflect.compare(a, b));

		for (file in sqlFiles) {
			if (!applied.exists(file)) {
				var sql = sys.io.File.getContent(dir + "/" + file);
				try {
					var statements = sql.split(';');
					for (stmt in statements) {
						stmt = StringTools.trim(stmt);
						if (stmt.length == 0)
							continue;
						execute(stmt);
					}
					execute("INSERT INTO migrations (name) VALUES (" + quoteString(file) + ");");
				} catch (e:Dynamic) {
					HybridLogger.error('Migration failed for ' + file + ': ' + e);
				}
			}
		}
	}

	public function buildSql(sql:String, params:Map<String, Dynamic>):String {
		if (params == null || params.keys().hasNext() == false)
			return sql;
		var out = new StringBuf();
		var i = 0;
		while (i < sql.length) {
			var ch = sql.charAt(i);
			if (ch == "'") {
				out.add(ch);
				i++;
				while (i < sql.length) {
					var c2 = sql.charAt(i);
					out.add(c2);
					if (c2 == "'") {
						if (i + 1 < sql.length && sql.charAt(i + 1) == "'") {
							out.add("'");
							i += 2;
							continue;
						} else {
							i++;
							break;
						}
					}
					i++;
				}
				continue;
			}
			if (ch == '@' || ch == ':') {
				var start = i + 1;
				while (start < sql.length && isIdentChar(sql.charCodeAt(start)))
					start++;
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

	private static inline function isIdentChar(code:Int):Bool {
		return (code >= 'A'.code && code <= 'Z'.code)
			|| (code >= 'a'.code && code <= 'z'.code)
			|| (code >= '0'.code && code <= '9'.code)
			|| code == '_'.code;
	}

	public inline function raw(v:String):RawSql
		return new RawSql(v);

	private function formatValue(v:Dynamic):String {
		if (v == null)
			return "NULL";
		if (Std.isOfType(v, RawSql))
			return cast(v, RawSql).value;
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = cast v;
			var parts = [];
			for (item in arr)
				parts.push(formatValueScalar(item));
			return '(' + parts.join(',') + ')';
		}
		return formatValueScalar(v);
	}

	private function formatValueScalar(v:Dynamic):String {
		if (v == null)
			return "NULL";
		if (Std.isOfType(v, String))
			return quoteString(cast v);
		if (Std.isOfType(v, Bool))
			return (cast v ? '1' : '0');
		if (Std.isOfType(v, Date)) {
			var d:Date = cast v;
			var formatted = DateTools.format(d, "%Y-%m-%d %H:%M:%S");
			return quoteString(formatted);
		}
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float))
			return Std.string(v);
		return quoteString(Std.string(v));
	}

	public function escapeString(str:String):String {
		return str == null ? null : StringTools.replace(str, "'", "''");
	}

	public function quoteString(str:String):String {
		return str == null ? null : "'" + StringTools.replace(str, "'", "''") + "'";
	}

	public function sanitize(str:String):String {
		return str == null ? null : escapeString(StringTools.trim(str));
	}
}

typedef WriteRequest = {
	var sql:String;
	var response:Deque<WriteResponse>;
	var returnId:Bool;
}

typedef WriteResponse = {
	var rs:ResultSet;
	var error:Dynamic;
	var lastId:Int;
}
