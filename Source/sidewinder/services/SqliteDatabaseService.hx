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
    private static var _connections:Map<String, sys.db.Connection> = new Map();
    private static var _connectionMutexes:Map<String, sys.thread.Mutex> = new Map();
    private static var _lastUsedAt:Map<String, Float> = new Map();
    private static var globalDbPath:String = null;
    private static var _mapMutex:sys.thread.Mutex = new sys.thread.Mutex();
    private static var _statsMutex:sys.thread.Mutex = new sys.thread.Mutex();
    
    private static function getConnectionsMap():Map<String, sys.db.Connection> {
        return _connections;
    }

    private static function getConnectionMutexesMap():Map<String, sys.thread.Mutex> {
        return _connectionMutexes;
    }

    private static function getLastUsedAtMap():Map<String, Float> {
        return _lastUsedAt;
    }

    private static function getGlobalMapMutex():sys.thread.Mutex {
        return _mapMutex;
    }

    private static function getGlobalStatsMutex():sys.thread.Mutex {
        return _statsMutex;
    }

    private static function ensureMutexes() {
        // No-op now as we use static initialization
    }


    private var dbPath:String;

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
        ensureMutexes();
        var rawPath = dbPath;
        this.dbPath = dbPath;
        if (this.dbPath == null) {
            getGlobalMapMutex().acquire();
            if (globalDbPath == null) {
                globalDbPath = Sys.getEnv("DATABASE_PATH");
                if (globalDbPath == null) {
                    // Final Linux fallback for containerized environments
                    #if linux
                    globalDbPath = "/app/data/data.db";
                    #end
                }
            }
            this.dbPath = globalDbPath;
            getGlobalMapMutex().release();
        }
        
        if (this.dbPath == null) {
            this.dbPath = "data.db"; // Absolute last resort
        }
        
        if (this.dbPath == null) {
            if (sys.FileSystem.exists("Export/hl/bin")) {
                this.dbPath = "Export/hl/bin/data.db";
            } else {
                this.dbPath = "data.db";
		}
	}
	
	try {
		if (this.dbPath != null) {
			// Resolve directory path
			var dir = haxe.io.Path.directory(this.dbPath);
			if (dir != "" && dir != "." && !sys.FileSystem.exists(dir)) {
				sys.FileSystem.createDirectory(dir);
			}

			var absolutePath = this.dbPath;
			try {
				absolutePath = sys.FileSystem.fullPath(this.dbPath);
			} catch(e:Dynamic) {}

			if (absolutePath != null) {
				this.dbPath = absolutePath;
			}
			
			// Convert to forward slashes for cross-platform map consistency
			this.dbPath = StringTools.replace(this.dbPath, "\\", "/");
		}
	} catch(e:Dynamic) {
	}
        
        var mapKey = normalizePath(this.dbPath);
        this.dbPath = mapKey;
        
        getGlobalMapMutex().acquire();
        try {
            var connections = getConnectionsMap();
            if (!connections.exists(mapKey)) {
                var dir = haxe.io.Path.directory(this.dbPath);
                if (dir != "" && !sys.FileSystem.exists(dir)) {
                    sys.FileSystem.createDirectory(dir);
                }
                
                var newConn = sys.db.Sqlite.open(this.dbPath);
                Sys.println("[SqliteDatabaseService] SQLite opened.");
                // WAL mode: concurrent reads with a single writer
                newConn.request("PRAGMA journal_mode=WAL;");
                // NORMAL sync: good balance of safety and performance
                newConn.request("PRAGMA synchronous=NORMAL;");
                // 10 second busy timeout - fast failure, not silent hang
                newConn.request("PRAGMA busy_timeout=10000;");
                newConn.request("PRAGMA foreign_keys=ON;");
                
                getConnectionsMap().set(mapKey, newConn);
                getConnectionMutexesMap().set(mapKey, new Mutex());
                
                getGlobalStatsMutex().acquire();
                getLastUsedAtMap().set(mapKey, Date.now().getTime());
                getGlobalStatsMutex().release();
            } else {
                getGlobalStatsMutex().acquire();
                getLastUsedAtMap().set(mapKey, Date.now().getTime());
                getGlobalStatsMutex().release();
            }
            
        } catch (e:Dynamic) {
            getGlobalMapMutex().release();
            HybridLogger.error('SqliteDatabaseService init error for ' + (this.dbPath != null ? this.dbPath : "null") + ': ' + e);
            throw e;
        }
        getGlobalMapMutex().release();
    }

    public static function hasOpenConnection(path:String):Bool {
        var mapKey = normalizePath(path);
        getGlobalMapMutex().acquire();
        var exists = getConnectionsMap().exists(mapKey);
        getGlobalMapMutex().release();
        return exists;
    }

    public static function getOpenConnectionCount():Int {
        getGlobalMapMutex().acquire();
        var count = 0;
        for (k in getConnectionsMap().keys()) count++;
        getGlobalMapMutex().release();
        return count;
    }

    public static function touchByPath(path:String):Void {
        var mapKey = normalizePath(path);
        getGlobalStatsMutex().acquire();
        getLastUsedAtMap().set(mapKey, Date.now().getTime());
        getGlobalStatsMutex().release();
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
        getGlobalStatsMutex().acquire();
        var time = getLastUsedAtMap().exists(mapKey) ? getLastUsedAtMap().get(mapKey) : 0.0;
        getGlobalStatsMutex().release();
        return time;
    }

    public static function closeByPath(path:String):Void {
        var mapKey = normalizePath(path);
        getGlobalMapMutex().acquire();
        try {
            if (getConnectionsMap().exists(mapKey)) {
                var conn = getConnectionsMap().get(mapKey);
                if (conn != null) {
                    try { conn.close(); } catch (e:Dynamic) {}
                }
                getConnectionsMap().remove(mapKey);
                getConnectionMutexesMap().remove(mapKey);
                getGlobalStatsMutex().acquire();
                getLastUsedAtMap().remove(mapKey);
                getGlobalStatsMutex().release();
            }
            getGlobalMapMutex().release();
        } catch (e:Dynamic) {
            getGlobalMapMutex().release();
        }
    }

    public function acquire():Connection return getConn();
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
        getGlobalMapMutex().acquire();
        try {
            var c = getConnectionsMap().get(this.dbPath);
            if (c == null) {
                c = sys.db.Sqlite.open(this.dbPath);
                c.request("PRAGMA journal_mode=WAL;");
                c.request("PRAGMA synchronous=NORMAL;");
                c.request("PRAGMA busy_timeout=10000;");
                c.request("PRAGMA foreign_keys=ON;");
                getConnectionsMap().set(this.dbPath, c);
            }
            if (!getConnectionMutexesMap().exists(this.dbPath)) {
                getConnectionMutexesMap().set(this.dbPath, new Mutex());
            }
            getGlobalMapMutex().release();
            return c;
        } catch (e:Dynamic) {
            getGlobalMapMutex().release();
            throw e;
        }
    }

    private function getSharedMutex():Mutex {
        getGlobalMapMutex().acquire();
        var m = getConnectionMutexesMap().get(dbPath);
        if (m == null) {
            m = new Mutex();
            getConnectionMutexesMap().set(dbPath, m);
        }
        getGlobalMapMutex().release();
        return m;
    }

    public function execute(sql:String, ?params:Map<String, Dynamic>):Void {
        var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
        var m = getSharedMutex();
        var c = getConn();
        
        m.acquire();
        try {
            c.request(finalSql);
            
            
            // Comments removed as logic is removed.
        } catch (e:Dynamic) {
            var errStr = Std.string(e);
            HybridLogger.error('[SqliteDB] execute FATAL ERROR: $errStr | SQL: ' + StringTools.replace(finalSql, "\n", " "));
            m.release();
            throw e;
        }
        m.release();
    }

    public function executeAndGetId(sql:String, ?params:Map<String, Dynamic>):Int {
        var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
        var m = getSharedMutex();
        var c = getConn();
        m.acquire();
        try {
            c.request(finalSql);
            var id = c.lastInsertId();
            m.release();
            return id;
        } catch (e:Dynamic) {
            HybridLogger.error('[SqliteDB] executeAndGetId ERROR: $e | SQL: $finalSql');
            m.release();
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
        var m = getSharedMutex();
        var c = getConn();
        m.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            var rs = c.request(finalSql);
            var result = new StaticResultSet(rs);
            m.release();
            return result;
        } catch (e:Dynamic) {
            HybridLogger.error('[SqliteDB] request ERROR: $e | SQL: $sql');
            m.release();
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
            } else if (Std.isOfType(val, Float)) {
                var s = Std.string(val);
                if (s.indexOf("e") != -1 || s.indexOf("E") != -1) {
                    // Manual formatting for large floats (timestamps) to avoid scientific notation
                    // This is a common HashLink stringification quirk for large numbers.
                    escapedVal = haxe.format.JsonPrinter.print(val);
                } else {
                    escapedVal = s;
                }
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


