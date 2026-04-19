package sidewinder.services;

import sys.thread.Thread;
import sys.thread.Deque;
import sys.thread.Mutex;
import sidewinder.interfaces.ILogDatabaseService;
import sidewinder.logging.HybridLogger;

/**
 * SQLite implementation of the log database service.
 * Points to logs.db by default.
 *
 * Uses an async writer thread for enqueue() so log writes don't block
 * API request threads. The logs.db file is only written to by this
 * writer thread, so no write-lock contention with the reader connection.
 */
class SqliteLogDatabaseService extends SqliteDatabaseService implements ILogDatabaseService {

    private var logDeque:Deque<Null<{sql:String, params:Map<String, Dynamic>}>>;
    private var pendingCount:Int = 0;
    private var pendingMutex:Mutex;
    private var writerReady:Bool = false;

    public function new(config:core.IServerConfig) {
        if (this.dbPath == null) {
            this.dbPath = Sys.getEnv("LOG_DATABASE_PATH");
            if (this.dbPath == null) {
                if (sys.FileSystem.exists("Export/hl/bin")) {
                    this.dbPath = "Export/hl/bin/logs.db";
                } else {
                    this.dbPath = "logs.db";
                }
            }
        }
        
        // Final sanity check/cleanup
        if (this.dbPath != null) {
            this.dbPath = StringTools.trim(this.dbPath);
            // Defensive: remove any leading/trailing quotes that might be in the env var
            if (StringTools.startsWith(this.dbPath, "\"")) this.dbPath = this.dbPath.substring(1);
            if (StringTools.endsWith(this.dbPath, "\"")) this.dbPath = this.dbPath.substring(0, this.dbPath.length - 1);
        }

        super(config);
        logDeque = new Deque();
        pendingMutex = new Mutex();
        startLogWriter();
    }

    private function startLogWriter():Void {
        var path = this.dbPath;
        var deque = logDeque;
        var pMutex = pendingMutex;
        Thread.create(function() {
            var wConn:sys.db.Connection = null;
            try {
                wConn = sys.db.Sqlite.open(path);
                wConn.request("PRAGMA journal_mode=WAL;");
                wConn.request("PRAGMA synchronous=NORMAL;");
                wConn.request("PRAGMA busy_timeout=5000;");
            } catch (e:Dynamic) {
                HybridLogger.error('[LogDB Writer] Failed to open $path: $e');
                return;
            }

            while (true) {
                var task = deque.pop(true); // blocking wait
                if (task == null) break;    // null = stop signal
                try {
                    var sql = SqliteDatabaseService.buildSqlStatic(task.sql, task.params);
                    wConn.request(sql);
                } catch (e:Dynamic) {
                    HybridLogger.error('[LogDB Writer] Write error: $e | SQL: ${task.sql}');
                }
                pMutex.acquire();
                pendingCount--;
                pMutex.release();
            }

            try { wConn.close(); } catch (e:Dynamic) {}
        });
    }

    /**
     * Non-blocking: queues the write and returns immediately.
     */
    override public function enqueue(sql:String, ?params:Map<String, Dynamic>):Void {
        pendingMutex.acquire();
        pendingCount++;
        pendingMutex.release();
        logDeque.push({sql: sql, params: params != null ? params : new Map()});
    }

    /**
     * Blocks until all previously enqueued writes have completed (max 5s).
     */
    override public function flush():Void {
        var deadline = Sys.time() + 5.0;
        while (Sys.time() < deadline) {
            pendingMutex.acquire();
            var n = pendingCount;
            pendingMutex.release();
            if (n <= 0) return;
            Sys.sleep(0.01);
        }
        HybridLogger.warn('[LogDB] flush() timed out with pending writes remaining');
    }
}
