package sidewinder.logging;

import sidewinder.interfaces.ILogProvider.LogEntry;

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
import sys.db.Sqlite;


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

		// Use SqliteDatabaseService to share the connection and ensure proper tracking/locking
		var service = sidewinder.services.SqliteDatabaseService.createWithPath(null, '$logDir/logs.db');
		conn = service.acquire();
		try {
			conn.request("CREATE TABLE IF NOT EXISTS internal_logs (created_at REAL, level TEXT, message TEXT)");
		} catch (e:Dynamic) {
			trace('SqliteLogProvider: Failed to ensure internal_logs table: $e');
		}
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
			// HL GC SIGNAL 11 fix: SqliteResultSet.hasNext() does List.push() during each
			// conn.request() call; the GC running mid-allocation corrupts the list.
			// Disable GC around each request() call (not the whole loop body, as string
			// allocations in between are safe to collect).
			#if hl hl.Gc.enable(false); #end
			conn.request("BEGIN TRANSACTION");
			#if hl hl.Gc.enable(true); #end
			for (entry in batch) {
				var ts = Date.now().getTime() / 1000.0;
				// GC-off covers string building (quoteString→StringTools.replace→String.split)
				// as well as conn.request() to prevent SIGNAL 11 on any allocation in this block.
				#if hl hl.Gc.enable(false); #end
				var sql = 'INSERT INTO internal_logs (created_at, level, message) VALUES ($ts, ${quoteString(entry.level)}, ${quoteString(entry.message)})';
				conn.request(sql);
				#if hl hl.Gc.enable(true); #end
			}
			#if hl hl.Gc.enable(false); #end
			conn.request("COMMIT");
			#if hl hl.Gc.enable(true); #end
			batch = [];
		} catch (e:Dynamic) {
			#if hl hl.Gc.enable(true); #end
			trace('SqliteLogProvider: Batch insert failed: $e');
			try {
				#if hl hl.Gc.enable(false); #end
				conn.request("ROLLBACK");
				#if hl hl.Gc.enable(true); #end
			} catch (err:Dynamic) {
				#if hl hl.Gc.enable(true); #end
			}
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




