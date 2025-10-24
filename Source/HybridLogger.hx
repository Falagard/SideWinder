package;

import sys.db.Connection;
import sys.db.Sqlite;
import sys.io.File;
import sys.FileSystem;
import sys.thread.Thread;
import sys.thread.Deque;
import haxe.Timer;
import Database;

typedef LogEntry = {
    time:String,
    level:String,
    message:String
}

enum abstract LogLevel(Int) from Int to Int {
    var DEBUG = 0;
    var INFO = 1;
    var WARN = 2;
    var ERROR = 3;
}

/**
 * HybridLogger
 * -------------
 * Thread-safe, multi-output logger with:
 * - Daily file rotation
 * - Batched SQLite inserts
 * - Configurable log level filtering
 * - Graceful shutdown flushing
 */
class HybridLogger {
    static var queue = new Deque<LogEntry>();
    static var workerStarted = false;
    static var stopRequested = false;

    static var logDir = "logs";
    static var currentDate:String;
    static var logFile:sys.io.FileOutput;

    static var sqliteEnabled = false;
    static var sqliteConn:Connection;
    static var sqliteBatch:Array<LogEntry> = [];
    static var lastFlushTime:Float = 0;

    static var batchSize = 20;
    static var batchDelay = 5.0; // seconds
    static var minLevel:LogLevel = LogLevel.DEBUG;

    // --- Initialization ---
    public static function init(?enableSqlite:Bool = false, ?minLvl:LogLevel = INFO) {
        if (workerStarted) return;
        workerStarted = true;
        sqliteEnabled = enableSqlite;
        minLevel = minLvl;

        if (!FileSystem.exists(logDir)) FileSystem.createDirectory(logDir);
        openLogFile();

        if (sqliteEnabled) {
            sqliteConn = Sqlite.open('$logDir/logs.db');
            sqliteConn.request('CREATE TABLE IF NOT EXISTS logs(time TEXT, level TEXT, message TEXT)');
        }

        // Spawn background worker thread
        Thread.create(() -> {
            while (!stopRequested) {
                var entry = queue.pop(true);
                if (entry == null) continue;

                rotateIfNeeded();

                // Write to file
                try {
                    var line = '[${entry.time}] ${entry.level.toUpperCase()} ${entry.message}\n';
                    logFile.writeString(line);
                } catch (e:Dynamic) {
                    trace('File log failed: ' + e);
                }

                // SQLite batching
                if (sqliteEnabled) {
                    sqliteBatch.push(entry);
                    var now = Timer.stamp();
                    if (sqliteBatch.length >= batchSize || (now - lastFlushTime) > batchDelay) {
                        flushToDb();
                        lastFlushTime = now;
                    }
                }
            }

            // On exit, flush any remaining logs
            try flushToDb() catch (e:Dynamic) {}
            try logFile.flush() catch (e:Dynamic) {}
            try logFile.close() catch (e:Dynamic) {}
            if (sqliteEnabled) try sqliteConn.close() catch (e:Dynamic) {}
        });
    }

    // --- Public Logging Methods ---

    public static inline function debug(msg:String) log("DEBUG", LogLevel.DEBUG, msg);
    public static inline function info(msg:String)  log("INFO", LogLevel.INFO, msg);
    public static inline function warn(msg:String)  log("WARN", LogLevel.WARN, msg);
    public static inline function error(msg:String) log("ERROR", LogLevel.ERROR, msg);

    static function log(levelStr:String, level:LogLevel, msg:String) {
        if (cast(level, Int) < cast(minLevel, Int)) return; // skip lower levels
        queue.add({
            time: Date.now().toString(),
            level: levelStr,
            message: msg
        });
    }

    // --- Helpers ---

    static function openLogFile() {
        currentDate = Date.now().toString().substr(0, 10); // YYYY-MM-DD
        var fileName = '$logDir/app-$currentDate.log';
        logFile = File.append(fileName);
    }

    static function rotateIfNeeded() {
        var today = Date.now().toString().substr(0, 10);
        if (today != currentDate) {
            try logFile.close() catch (e:Dynamic) {}
            openLogFile();
        }
    }

    static function flushToDb() {
        if (!sqliteEnabled || sqliteBatch.length == 0) return;
        try {
            sqliteConn.request("BEGIN TRANSACTION");
            for (entry in sqliteBatch) {

                var sql = 'INSERT INTO logs VALUES (${Database.quoteString(entry.time)}, ${Database.quoteString(entry.level)}, ${Database.quoteString(entry.message)})';
                sqliteConn.request(sql);
            }
            sqliteConn.request("COMMIT");
            sqliteBatch = [];
        } catch (e:Dynamic) {
            trace("SQLite batch insert failed: " + e);
            try sqliteConn.request("ROLLBACK") catch (err:Dynamic) {}
        }
    }

    // --- Graceful shutdown ---
    public static function shutdown() {
        stopRequested = true;
        // Push a null entry to wake up the queue
        queue.add(null);
        Sys.sleep(0.5); // allow worker to finish flushing
    }
}
