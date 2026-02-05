package sidewinder;

import sys.db.Connection;
import sys.db.Sqlite;
import sidewinder.ILogProvider;
import sidewinder.ILogProvider;
import sys.FileSystem;
import haxe.Timer;

/**
 * SQLite-based log provider with batching for performance.
 */
class SqliteLogProvider implements ILogProvider {
	private var conn:Connection;
	private var batch:Array<LogEntry> = [];
	private var lastFlushTime:Float = 0;
	private var batchSize:Int;
	private var batchDelay:Float;

	public function new(logDir:String = "logs", batchSize:Int = 20, batchDelay:Float = 5.0) {
		this.batchSize = batchSize;
		this.batchDelay = batchDelay;

		if (!FileSystem.exists(logDir)) {
			FileSystem.createDirectory(logDir);
		}

		conn = Sqlite.open('$logDir/logs.db');
		conn.request('CREATE TABLE IF NOT EXISTS logs(time TEXT, level TEXT, message TEXT)');
		lastFlushTime = Timer.stamp();
	}

	public function log(entry:LogEntry):Void {
		batch.push(entry);
		var now = Timer.stamp();
		if (batch.length >= batchSize || (now - lastFlushTime) > batchDelay) {
			flush();
			lastFlushTime = now;
		}
	}

	public function flush():Void {
		if (batch.length == 0)
			return;

		try {
			conn.request("BEGIN TRANSACTION");
			for (entry in batch) {
				var sql = 'INSERT INTO logs VALUES (${quoteString(entry.time)}, ${quoteString(entry.level)}, ${quoteString(entry.message)})';
				conn.request(sql);
			}
			conn.request("COMMIT");
			batch = [];
		} catch (e:Dynamic) {
			trace('SqliteLogProvider: Batch insert failed: $e');
			try {
				conn.request("ROLLBACK");
			} catch (err:Dynamic) {}
		}
	}

	public function shutdown():Void {
		flush();
		try {
			conn.close();
		} catch (e:Dynamic) {
			trace('SqliteLogProvider: Failed to shutdown: $e');
		}
	}

	private function quoteString(str:String):String {
		return str == null ? "NULL" : "'" + StringTools.replace(str, "'", "''") + "'";
	}
}
