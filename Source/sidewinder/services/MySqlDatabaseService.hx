package sidewinder.services;
import sidewinder.interfaces.User;

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
import sys.db.Mysql;
import sys.db.ResultSet;
import sys.thread.Mutex;
import DateTools;


/**
 * MySQL implementation of the database service.
 * Standardized for IDatabaseService.
 */
class MySqlDatabaseService implements IDatabaseService {
	static inline var MAX_POOL_SIZE = 8;

	var mutex = new Mutex();
	var pool:Array<Connection> = [];

	var host:String;
	var port:Int;
	var database:String;
	var user:String;
	var password:String;

	public function new() {
		this.host = Sys.getEnv("MYSQL_HOST") != null ? Sys.getEnv("MYSQL_HOST") : "localhost";
		var portStr = Sys.getEnv("MYSQL_PORT");
		this.port = portStr != null ? Std.parseInt(portStr) : 3306;
		this.database = Sys.getEnv("MYSQL_DATABASE") != null ? Sys.getEnv("MYSQL_DATABASE") : "sidewinder";
		this.user = Sys.getEnv("MYSQL_USER") != null ? Sys.getEnv("MYSQL_USER") : "root";
		this.password = Sys.getEnv("MYSQL_PASSWORD") != null ? Sys.getEnv("MYSQL_PASSWORD") : "";
	}

	public function acquire():Connection {
		mutex.acquire();
		var conn = pool.pop();
		mutex.release();

		if (conn != null)
			return conn;

		var c = Mysql.connect({
			host: host,
			port: port,
			database: database,
			user: user,
			pass: password
		});

		return c;
	}

	public function release(conn:Connection):Void {
		mutex.acquire();
		if (pool.length < MAX_POOL_SIZE)
			pool.push(conn);
		else
			conn.close();
		mutex.release();
	}

	public function requestRead(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		return requestWithParams(sql, params);
	}

	public inline function read(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		return requestRead(sql, params);
	}

	public function requestWrite(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		return requestWithParams(sql, params);
	}

	public inline function write(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		return requestWrite(sql, params);
	}

	public function requestWithParams(sql:String, ?params:Map<String, Dynamic>):ResultSet {
		var conn = acquire();
		var finalSql = (params != null) ? buildSql(sql, params) : sql;
		var rs = conn.request(finalSql);
		release(conn);
		return rs;
	}

	public function execute(sql:String, ?params:Map<String, Dynamic>):Void {
		requestWrite(sql, params);
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

	public function runMigrations():Void {
		var conn = acquire();
		var rs = conn.request("SELECT name FROM migrations;");
		var applied = new Map<String, Bool>();
		while (rs.hasNext()) {
			var record = rs.next();
			applied.set(record.name, true);
		}
		var dir = "migrations/mysql";
		var files = sys.FileSystem.readDirectory(dir);
		var sqlFiles = files.filter(f -> StringTools.endsWith(f, ".sql"));
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
