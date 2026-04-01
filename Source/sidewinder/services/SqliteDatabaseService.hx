package sidewinder.services;
#if (html5 && !sys)
#error "SqliteDatabaseService is not available on HTML5. Use a client-side storage service instead."
#end

import sys.db.Connection;
import sys.db.ResultSet;
import sys.db.Sqlite;
import sys.thread.Mutex;
import sys.thread.Thread;
import sys.thread.Deque;
import sidewinder.interfaces.IDatabaseService;
import sidewinder.logging.HybridLogger;
import core.IServerConfig;

/**
 * SQLite implementation of the database service.
 * Supports multiple thread-safe connections and non-blocking writes via enqueue().
 */
class SqliteDatabaseService implements IDatabaseService {
    private static var connections:Map<String, Connection> = new Map();
    private static var connectionMutexes:Map<String, Mutex> = new Map();
    private static var deques:Map<String, Deque<{sql:String, params:Map<String, Dynamic>}>> = new Map();
    private static var pendingCounts:Map<String, Int> = new Map();
    private static var writerStarted:Map<String, Bool> = new Map();
    private static var lastUsedAt:Map<String, Float> = new Map();
    private static var globalMutex:Mutex = new Mutex();

    private var dbPath:String;
    private var conn:Connection;
    private var deque:Deque<{sql:String, params:Map<String, Dynamic>}>;
    private var currentMutex:Mutex;

    public static function normalizePath(path:String):String {
        if (path == null) return null;
        var p = path;
        try {
            p = sys.FileSystem.fullPath(p).split("\\").join("/");
        } catch (e:Dynamic) {}
        return p.toLowerCase();
    }

    public static function createWithPath(config:core.IServerConfig, dbPath:String):SqliteDatabaseService {
        var svc = Type.createEmptyInstance(SqliteDatabaseService);
        svc.init(config, dbPath);
        return svc;
    }

    public function new(config:core.IServerConfig) {
        init(config, null);
    }

    private function init(config:core.IServerConfig, dbPath:String) {
        this.dbPath = dbPath;
        if (this.dbPath == null) this.dbPath = Sys.getEnv("DATABASE_PATH");
        if (this.dbPath == null) {
            // Heuristic for project structure
            if (sys.FileSystem.exists("Export/hl/bin")) {
                this.dbPath = "Export/hl/bin/data.db";
            } else {
                this.dbPath = "data.db";
            }
        }
        
        var mapKey = normalizePath(this.dbPath);
        this.dbPath = mapKey; // Store normalized path
        
        // Initialize connection for this dbPath (shared across many instances)
        globalMutex.acquire();
        try {
            if (!connections.exists(mapKey)) {
                HybridLogger.info('CREATING NEW SHARED CONNECTION for $dbPath');
                var dir = haxe.io.Path.directory(this.dbPath);
                if (dir != "" && !sys.FileSystem.exists(dir)) {
                    sys.FileSystem.createDirectory(dir);
                }
                
                var newConn = Sqlite.open(this.dbPath);
                newConn.request("PRAGMA journal_mode=WAL;");
                newConn.request("PRAGMA synchronous=NORMAL;");
                newConn.request("PRAGMA busy_timeout=5000;");
                newConn.request("PRAGMA foreign_keys=ON;");
                
                connections.set(mapKey, newConn);
                connectionMutexes.set(mapKey, new Mutex());
                deques.set(mapKey, new Deque());
                pendingCounts.set(mapKey, 0);
            } else {
                HybridLogger.info('USING EXISTING SHARED CONNECTION for $dbPath');
            }
            
            this.conn = connections.get(mapKey);
            this.currentMutex = connectionMutexes.get(mapKey);
            this.deque = deques.get(mapKey);

            if (!writerStarted.exists(mapKey)) {
                writerStarted.set(mapKey, true);
                startWriterThread(mapKey, this.dbPath, this.deque);
            }
            
            lastUsedAt.set(mapKey, Date.now().getTime());
        } catch (e:Dynamic) {
            globalMutex.release();
            HybridLogger.error("Failed to initialize shared SQLite connection for " + this.dbPath + ": " + e);
            throw e;
        }
        globalMutex.release();
    }

    private static function startWriterThread(mapKey:String, path:String, deque:Deque<{sql:String, params:Map<String, Dynamic>}>) {
        Thread.create(function() {
            var writerConn:Connection = null;
            try {
                writerConn = Sqlite.open(path);
                writerConn.request("PRAGMA journal_mode=WAL;");
                writerConn.request("PRAGMA synchronous=NORMAL;");
                writerConn.request("PRAGMA busy_timeout=5000;");
            } catch (e:Dynamic) {
                HybridLogger.error('Failed to start SQLite writer thread for $path: $e');
                return;
            }

            while (true) {
                var task = deque.pop(true);
                if (task == null) break; // Shutdown signal
                
                try {
                    var finalSql = buildSqlStatic(task.sql, task.params);
                    writerConn.request(finalSql);
                } catch (e:Dynamic) {
                    HybridLogger.error('Async write error to $path: $e | SQL: ${task.sql}');
                }
                
                globalMutex.acquire();
                var count = pendingCounts.get(mapKey);
                if (count != null) pendingCounts.set(mapKey, count - 1);
                globalMutex.release();
            }

            if (writerConn != null) {
                try {
                    writerConn.request("PRAGMA wal_checkpoint(PASSIVE);");
                    writerConn.close();
                } catch (e:Dynamic) {}
            }
            HybridLogger.info('SQLite writer thread for $path SHUTDOWN CLEANLY');
        });
    }

    public static function hasOpenConnection(path:String):Bool {
        var mapKey = normalizePath(path);
        globalMutex.acquire();
        var exists = connections.exists(mapKey);
        globalMutex.release();
        return exists;
    }

    public static function getOpenConnectionCount():Int {
        globalMutex.acquire();
        var count = 0;
        for (k in connections.keys()) count++;
        globalMutex.release();
        return count;
    }

    public static function touchByPath(path:String):Void {
        var mapKey = normalizePath(path);
        globalMutex.acquire();
        lastUsedAt.set(mapKey, Date.now().getTime());
        globalMutex.release();
    }

    public static function getLastUsedAt(path:String):Float {
        var mapKey = normalizePath(path);
        globalMutex.acquire();
        var time = lastUsedAt.exists(mapKey) ? lastUsedAt.get(mapKey) : 0.0;
        globalMutex.release();
        return time;
    }

    public static function closeByPath(path:String):Void {
        var mapKey = normalizePath(path);
        globalMutex.acquire();
        try {
            if (connections.exists(mapKey)) {
                HybridLogger.info('CLOSING SHARED CONNECTION for $path');
                
                // 1. Flush pending writes by sending shutdown signal
                var dq = deques.get(mapKey);
                if (dq != null) {
                    dq.push(null); // Shutdown signal
                }
                
                // 2. Wait for pending count to reach 0 (with timeout)
                globalMutex.release();
                var startTime = Date.now().getTime();
                while (true) {
                    globalMutex.acquire();
                    var count = pendingCounts.get(mapKey);
                    if (count == null || count <= 0) {
                        globalMutex.release();
                        break;
                    }
                    globalMutex.release();
                    Sys.sleep(0.01);
                    if (Date.now().getTime() - startTime > 10000) {
                        HybridLogger.warn('Timeout flushing SQLite writes for $path');
                        break;
                    }
                }
                
                // Give writer thread a tiny bit of time to close itself
                Sys.sleep(0.1);
                
                globalMutex.acquire();
                
                // 3. Perform checkpoint and close connection
                var conn = connections.get(mapKey);
                if (conn != null) {
                    try {
                        conn.request("PRAGMA wal_checkpoint(PASSIVE);");
                        conn.close();
                    } catch (e:Dynamic) {}
                }

                // 4. Clean up maps
                connections.remove(mapKey);
                connectionMutexes.remove(mapKey);
                deques.remove(mapKey);
                pendingCounts.remove(mapKey);
                writerStarted.remove(mapKey);
                lastUsedAt.remove(mapKey);
            }
        } catch (e:Dynamic) {
             HybridLogger.error('Error in closeByPath for $path: $e');
        }
        globalMutex.release();
    }

    public function acquire():Connection return conn;
    public function release(conn:Connection):Void {}

    public function write(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        execute(sql, params);
        return null;
    }

    public function read(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        return request(sql, params);
    }

    public function requestRead(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        return read(sql, params);
    }

    public function requestWrite(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        return write(sql, params);
    }

    public function requestWithParams(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        return read(sql, params);
    }

    public function execute(sql:String, ?params:Map<String, Dynamic>):Void {
        touchByPath(dbPath);
        var thread = sys.thread.Thread.current();
        var tid = "T" + Std.string(Type.enumIndex(cast thread)); // Try to get a unique-ish string
        if (tid == "T") tid = "T" + StringTools.hex(Std.parseInt(Std.string(thread))); // Fallback for HL
        currentMutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            var trimmedSql = StringTools.trim(finalSql).toUpperCase();
            var isWrite = trimmedSql.indexOf("INSERT") == 0 || trimmedSql.indexOf("UPDATE") == 0 || trimmedSql.indexOf("DELETE") == 0;
            
            if (isWrite) {
                HybridLogger.info('[$tid] SQL EXECUTE: $finalSql');
            }
            
            var rs = conn.request(finalSql);
            
            // Check for immediate success or side effects
            if (isWrite) {
                // If it's a critical table, force a tiny read to trigger driver error detection
                if (trimmedSql.indexOf("INSERT INTO UPLOAD_SESSIONS") == 0 || trimmedSql.indexOf("INSERT INTO API_KEYS") == 0) {
                   conn.request("SELECT 1;");
                   // Explicitly trigger a WAL checkpoint to ensure visibility on other threads/processes
                   // PRAGMA wal_checkpoint(FULL) ensures that all frames are written out
                   conn.request("PRAGMA wal_checkpoint(PASSIVE);");
                }
            }

            currentMutex.release();
        } catch (e:Dynamic) {
            currentMutex.release();
            HybridLogger.error('SqliteDatabaseService.execute error: $e | SQL: $sql');
            throw e;
        }
    }

    public function executeAndGetId(sql:String, ?params:Map<String, Dynamic>):Int {
        touchByPath(dbPath);
        currentMutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            conn.request(finalSql);
            var id = conn.lastInsertId();
            currentMutex.release();
            return id;
        } catch (e:Dynamic) {
            currentMutex.release();
            HybridLogger.error('SqliteDatabaseService.executeAndGetId error: $e | SQL: $sql');
            throw e;
        }
    }

    public function enqueue(sql:String, ?params:Map<String, Dynamic>):Void {
        globalMutex.acquire();
        var count = pendingCounts.get(dbPath);
        pendingCounts.set(dbPath, count + 1);
        globalMutex.release();
        
        deque.push({sql: sql, params: params});
    }

    public function flush():Void {
        while (true) {
            globalMutex.acquire();
            var count = pendingCounts.get(dbPath);
            globalMutex.release();
            if (count <= 0) break;
            Sys.sleep(0.001);
        }
    }

    public function request(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        touchByPath(dbPath);
        var tid = Std.string(sys.thread.Thread.current());
        currentMutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            // HybridLogger.info('[$tid] SQL REQUEST: $finalSql');
            var rs = conn.request(finalSql);
            var result = new StaticResultSet(rs);
            currentMutex.release();
            return result;
        } catch (e:Dynamic) {
            currentMutex.release();
            HybridLogger.error('SqliteDatabaseService.request error: $e | SQL: $sql');
            throw e;
        }
    }

    public function beginTransaction():Void execute("BEGIN TRANSACTION;");
    public function commit():Void execute("COMMIT;");
    public function rollback():Void execute("ROLLBACK;");

    public function runMigrations():Void {
        runMigrationsWithPath("migrations/sqlite");
    }

    public function runMigrationsWithPath(dir:String):Void {
        // Use a distinct migrations table for non-default paths to avoid conflicts
        var table = (dir == "migrations/sqlite") ? "migrations" : "_migrations";
        execute('CREATE TABLE IF NOT EXISTS $table (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TEXT DEFAULT CURRENT_TIMESTAMP);');

        var rs = request('SELECT name FROM $table;');
        var applied = new Map<String, Bool>();
        while (rs.hasNext()) {
            applied.set(rs.next().name, true);
        }

        if (!sys.FileSystem.exists(dir)) return;

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
                        if (stmt.length == 0) continue;
                        execute(stmt);
                    }
                    execute('INSERT INTO $table (name) VALUES (@name);', ["name" => file]);
                } catch (e:Dynamic) {
                    HybridLogger.error('Migration failed for ' + file + ' in ' + dir + ': ' + e);
                    throw e;
                }
            }
        }
    }

    public static function buildSqlStatic(sql:String, params:Map<String, Dynamic>):String {
        if (params == null || !params.keys().hasNext()) return sql;
        var result = sql;
        
        var keys = [];
        for (k in params.keys()) keys.push(k);
        keys.sort((a, b) -> b.length - a.length);

        for (key in keys) {
            var val = params.get(key);
            var escapedVal = "";
            
            if (val == null) {
                escapedVal = "NULL";
            } else if (Std.isOfType(val, String)) {
                escapedVal = "'" + StringTools.replace(Std.string(val), "'", "''") + "'";
            } else if (Std.isOfType(val, Bool)) {
                escapedVal = val ? "1" : "0";
            } else if (Std.isOfType(val, Date)) {
                var time = val.getTime() / 1000.0;
                escapedVal = Std.string(time);
            } else if (Std.isOfType(val, sidewinder.interfaces.IDatabaseService.RawSql)) {
                escapedVal = cast(val, sidewinder.interfaces.IDatabaseService.RawSql).value;
            } else {
                escapedVal = Std.string(val);
            }
            
            result = StringTools.replace(result, "@" + key, escapedVal);
        }
        return result;
    }

    public function buildSql(sql:String, params:Map<String, Dynamic>):String return buildSqlStatic(sql, params);
    public function escapeString(str:String):String return StringTools.replace(str, "'", "''");
    public function quoteString(str:String):String return "'" + escapeString(str) + "'";
    public function sanitize(str:String):String return escapeString(StringTools.trim(str));
    public function raw(v:String):sidewinder.interfaces.IDatabaseService.RawSql return new sidewinder.interfaces.IDatabaseService.RawSql(v);
}

class StaticResultSet implements sys.db.ResultSet {
    var rows:Array<Dynamic>;
    var index:Int = 0;

    public function new(rs:sys.db.ResultSet) {
        rows = [];
        if (rs != null) {
            while (rs.hasNext()) {
                var row = rs.next();
                // Deep copy row if it's dynamic to avoid driver reuse issues
                var copy = {};
                for (f in Reflect.fields(row)) {
                    Reflect.setField(copy, f, Reflect.field(row, f));
                }
                rows.push(copy);
            }
        }
    }

    public var length(get, null):Int;
    public var nfields(get, null):Int;
    function get_length() return rows.length;
    function get_nfields() return rows.length > 0 ? Reflect.fields(rows[0]).length : 0;

    public function hasNext():Bool return index < rows.length;
    public function next():Dynamic return rows[index++];
    public function results():List<Dynamic> {
        var l = new List<Dynamic>();
        for (r in rows) l.add(r);
        return l;
    }
    public function getFieldsNames():Array<String> return rows.length > 0 ? Reflect.fields(rows[0]) : [];
    public function getResult(n:Int):String return "";
    public function getIntResult(n:Int):Int return 0;
    public function getFloatResult(n:Int):Float return 0;
    public function getStringResult(n:Int):String return "";
}
