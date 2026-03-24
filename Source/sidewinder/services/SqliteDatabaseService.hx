package sidewinder.services;

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
 * Supports multiple database files and non-blocking writes via enqueue().
 */
class SqliteDatabaseService implements IDatabaseService {
    private static var connections:Map<String, Connection> = new Map();
    private static var mutexes:Map<String, Mutex> = new Map();
    private static var deques:Map<String, Deque<{sql:String, params:Map<String, Dynamic>}>> = new Map();
    private static var globalMutex:Mutex = new Mutex();

    private var dbPath:String;
    private var conn:Connection;
    private var mutex:Mutex;
    private var deque:Deque<{sql:String, params:Map<String, Dynamic>}>;

    public function new(config:IServerConfig) {
        if (this.dbPath == null) this.dbPath = "Export/hl/bin/data.db";
        
        globalMutex.acquire();
        if (!connections.exists(dbPath)) {
            try {
                var dir = haxe.io.Path.directory(dbPath);
                if (dir != "" && !sys.FileSystem.exists(dir)) {
                    sys.FileSystem.createDirectory(dir);
                }
                
                var c = Sqlite.open(dbPath);
                c.request("PRAGMA journal_mode=WAL;");
                c.request("PRAGMA synchronous=NORMAL;");
                c.request("PRAGMA busy_timeout=5000;");
                c.request("PRAGMA foreign_keys=ON;");
                
                connections.set(dbPath, c);
                mutexes.set(dbPath, new Mutex());
                var d = new Deque<{sql:String, params:Map<String, Dynamic>}>();
                deques.set(dbPath, d);
                
                startWriterThread(dbPath, c, mutexes.get(dbPath), d);
                HybridLogger.info('SqliteDatabaseService initialized and writer thread started for: $dbPath');
            } catch (e:Dynamic) {
                globalMutex.release();
                HybridLogger.error("Failed to initialize SQLite connection for " + dbPath + ": " + e);
                throw e;
            }
        }
        
        this.conn = connections.get(dbPath);
        this.mutex = mutexes.get(dbPath);
        this.deque = deques.get(dbPath);
        globalMutex.release();
    }

    private static function startWriterThread(path:String, conn:Connection, mutex:Mutex, deque:Deque<{sql:String, params:Map<String, Dynamic>}>) {
        Thread.create(function() {
            while (true) {
                var task = deque.pop(true);
                if (task == null) continue;
                
                mutex.acquire();
                try {
                    var finalSql = buildSqlStatic(task.sql, task.params);
                    conn.request(finalSql);
                } catch (e:Dynamic) {
                    HybridLogger.error('Async write error to $path: $e | SQL: ${task.sql}');
                }
                mutex.release();
            }
        });
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
        mutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            conn.request(finalSql);
            mutex.release();
        } catch (e:Dynamic) {
            mutex.release();
            HybridLogger.error('SqliteDatabaseService.execute error: $e | SQL: $sql');
            throw e;
        }
    }

    public function executeAndGetId(sql:String, ?params:Map<String, Dynamic>):Int {
        mutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            conn.request(finalSql);
            var id = conn.lastInsertId();
            mutex.release();
            return id;
        } catch (e:Dynamic) {
            mutex.release();
            throw e;
        }
    }

    public function enqueue(sql:String, ?params:Map<String, Dynamic>):Void {
        deque.push({sql: sql, params: params});
    }

    public function request(sql:String, ?params:Map<String, Dynamic>):ResultSet {
        mutex.acquire();
        try {
            var finalSql = (params != null) ? buildSqlStatic(sql, params) : sql;
            var rs = conn.request(finalSql);
            var staticRs = new StaticResultSet(rs);
            mutex.release();
            return staticRs;
        } catch (e:Dynamic) {
            mutex.release();
            HybridLogger.error('SqliteDatabaseService.request error: $e | SQL: $sql');
            throw e;
        }
    }

    public function beginTransaction():Void execute("BEGIN TRANSACTION;");
    public function commit():Void execute("COMMIT;");
    public function rollback():Void execute("ROLLBACK;");

    public function runMigrations():Void {
        var dir = "migrations/sqlite";
        execute('CREATE TABLE IF NOT EXISTS migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TEXT DEFAULT CURRENT_TIMESTAMP);');

        var rs = request("SELECT name FROM migrations;");
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
                    execute("INSERT INTO migrations (name) VALUES (@name);", ["name" => file]);
                } catch (e:Dynamic) {
                    HybridLogger.error('Migration failed for ' + file + ': ' + e);
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
        while (rs != null && rs.hasNext()) {
            rows.push(rs.next());
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
