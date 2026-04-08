package sidewinder.services;
#if (html5 && !sys)
#error "SqliteDatabaseService is not available on HTML5. Use a client-side storage service instead."
#end

import sys.db.Connection;
import sys.db.ResultSet;
import sys.db.Sqlite;
import sys.thread.Mutex;
import sidewinder.interfaces.IDatabaseService;
import sidewinder.logging.HybridLogger;
import core.IServerConfig;

/**
 * SQLite implementation of the database service.
 * V17 - Single connection per DB path, single mutex, no writer thread.
 * The writer thread was opening a second connection which competed for write
 * locks with the API thread, causing 30-second busy_timeout waits.
 */
class SqliteDatabaseService implements IDatabaseService {
    private static var connections:Map<String, Connection> = new Map();
    private static var connectionMutexes:Map<String, Mutex> = new Map();
    private static var lastUsedAt:Map<String, Float> = new Map();
    
    private static var mapMutex:Mutex = new Mutex();
    private static var statsMutex:Mutex = new Mutex();

    private var dbPath:String;
    // NOTE: conn is cached for perf but refreshed via getConn() if closed
    private var conn:Connection;
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
            if (sys.FileSystem.exists("Export/hl/bin")) {
                this.dbPath = "Export/hl/bin/data.db";
            } else {
                this.dbPath = "data.db";
            }
        }
        
        var tid = getThreadId();
        var mapKey = normalizePath(this.dbPath);
        this.dbPath = mapKey;
        
        mapMutex.acquire();
        try {
            if (!connections.exists(mapKey)) {
                HybridLogger.info('[$tid] CREATING NEW SHARED CONNECTION for $dbPath');
                var dir = haxe.io.Path.directory(this.dbPath);
                if (dir != "" && !sys.FileSystem.exists(dir)) {
                    sys.FileSystem.createDirectory(dir);
                }
                
                var newConn = sys.db.Sqlite.open(this.dbPath);
                // WAL mode: concurrent reads with a single writer
                newConn.request("PRAGMA journal_mode=WAL;");
                // NORMAL sync: good balance of safety and performance
                newConn.request("PRAGMA synchronous=NORMAL;");
                // 10 second busy timeout - fast failure, not silent hang
                newConn.request("PRAGMA busy_timeout=10000;");
                newConn.request("PRAGMA foreign_keys=ON;");
                
                connections.set(mapKey, newConn);
                connectionMutexes.set(mapKey, new Mutex());
                
                statsMutex.acquire();
                lastUsedAt.set(mapKey, Date.now().getTime());
                statsMutex.release();
            } else {
                HybridLogger.info('[$tid] USING EXISTING SHARED CONNECTION for $dbPath');
                statsMutex.acquire();
                lastUsedAt.set(mapKey, Date.now().getTime());
                statsMutex.release();
            }
            
            this.conn = connections.get(mapKey);
            this.currentMutex = connectionMutexes.get(mapKey);
        } catch (e:Dynamic) {
            mapMutex.release();
            HybridLogger.error('[$tid] init error for $dbPath: $e');
            throw e;
        }
        mapMutex.release();
    }

    public static function hasOpenConnection(path:String):Bool {
        var mapKey = normalizePath(path);
        mapMutex.acquire();
        var exists = connections.exists(mapKey);
        mapMutex.release();
        return exists;
    }

    public static function getOpenConnectionCount():Int {
        mapMutex.acquire();
        var count = 0;
        for (k in connections.keys()) count++;
        mapMutex.release();
        return count;
    }

    public static function touchByPath(path:String):Void {
        var mapKey = normalizePath(path);
        statsMutex.acquire();
        lastUsedAt.set(mapKey, Date.now().getTime());
        statsMutex.release();
    }

    public function getThreadId():String {
        var thread = sys.thread.Thread.current();
        var tid = Std.string(thread);
        tid = StringTools.replace(tid, "Thread", "T");
        tid = StringTools.replace(tid, "<", "");
        tid = StringTools.replace(tid, ">", "");
        return tid;
    }

    public static function getLastUsedAt(path:String):Float {
        var mapKey = normalizePath(path);
        statsMutex.acquire();
        var time = lastUsedAt.exists(mapKey) ? lastUsedAt.get(mapKey) : 0.0;
        statsMutex.release();
        return time;
    }

    public static function closeByPath(path:String):Void {
        var mapKey = normalizePath(path);
        HybridLogger.info('[closeByPath] Closing $path');
        mapMutex.acquire();
        try {
            if (connections.exists(mapKey)) {
                var conn = connections.get(mapKey);
                if (conn != null) {
                    try { conn.close(); } catch (e:Dynamic) {}
                }
                connections.remove(mapKey);
                connectionMutexes.remove(mapKey);
                statsMutex.acquire();
                lastUsedAt.remove(mapKey);
                statsMutex.release();
            }
            mapMutex.release();
        } catch (e:Dynamic) {
            mapMutex.release();
            HybridLogger.error('[closeByPath] Error: $e');
        }
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

    /**
     * Returns the active connection for this DB path, reopening if it was
     * closed by closeByPath() (e.g. between seeding and integration test runs).
     * Must be called while holding currentMutex.
     */
    private function getConn():Connection {
        var c = connections.get(dbPath);
        if (c == null) {
            HybridLogger.info('[SqliteDB] Reopening closed connection for $dbPath');
            c = sys.db.Sqlite.open(dbPath);
            c.request("PRAGMA journal_mode=WAL;");
            c.request("PRAGMA synchronous=NORMAL;");
            c.request("PRAGMA busy_timeout=10000;");
            c.request("PRAGMA foreign_keys=ON;");
            connections.set(dbPath, c);
            if (!connectionMutexes.exists(dbPath)) {
                connectionMutexes.set(dbPath, this.currentMutex);
            }
        }
        this.conn = c;
        return c;
    }

    public function execute(sql:String, ?params:Map<String, Dynamic>):Void {
        var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
        currentMutex.acquire();
        try {
            getConn().request(finalSql);
            currentMutex.release();
        } catch (e:Dynamic) {
            currentMutex.release();
            HybridLogger.error('[SqliteDB] execute ERROR: $e | SQL: $finalSql');
            throw e;
        }
    }

    public function executeAndGetId(sql:String, ?params:Map<String, Dynamic>):Int {
        var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
        currentMutex.acquire();
        try {
            var c = getConn();
            c.request(finalSql);
            var id = c.lastInsertId();
            currentMutex.release();
            return id;
        } catch (e:Dynamic) {
            currentMutex.release();
            HybridLogger.error('[SqliteDB] executeAndGetId ERROR: $e | SQL: $finalSql');
            throw e;
        }
    }

    // enqueue/flush: now synchronous (no separate writer thread)
    public function enqueue(sql:String, ?params:Map<String, Dynamic>):Void {
        execute(sql, params);
    }

    public function flush():Void {
        // No-op: enqueue is now synchronous
    }

    public function request(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        currentMutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            var rs = getConn().request(finalSql);
            var result = new StaticResultSet(rs);
            currentMutex.release();
            return result;
        } catch (e:Dynamic) {
            currentMutex.release();
            HybridLogger.error('[SqliteDB] request ERROR: $e | SQL: $sql');
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
