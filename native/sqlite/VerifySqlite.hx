import sys.db.Sqlite;
import sys.db.Connection;

class VerifySqlite {
    static function main() {
        try {
            var conn = Sqlite.open(":memory:");
            trace("SQLITE Version: " + conn.request("SELECT sqlite_version() as v;").next().v);
            
            trace("--- Compile Options ---");
            var rs = conn.request("PRAGMA compile_options;");
            while (rs.hasNext()) {
                trace("Option: " + rs.next().compile_options);
            }
            
            trace("--- Feature Verification ---");
            
            // Math Functions
            try {
                var res:Float = conn.request("SELECT sin(1.0) as val;").next().val;
                trace("Math Functions (sin(1.0)): SUCCESS (" + Std.string(res) + ")");
            } catch(e:Dynamic) trace("Math Functions: FAILED (" + e + ")");
            
            // JSON1
            try {
                var res:String = conn.request("SELECT json('{\"a\":1}') as val;").next().val;
                trace("JSON1 (json): SUCCESS (" + res + ")");
            } catch(e:Dynamic) trace("JSON1: FAILED (" + e + ")");
            
            // FTS5
            try {
                conn.request("CREATE VIRTUAL TABLE fts_test USING fts5(content);");
                trace("FTS5: SUCCESS");
            } catch(e:Dynamic) trace("FTS5: FAILED (" + e + ")");
            
            // RTree
            try {
                conn.request("CREATE VIRTUAL TABLE rtree_test USING rtree(id, minX, maxX, minY, maxY);");
                trace("RTREE: SUCCESS");
            } catch(e:Dynamic) trace("RTREE: FAILED (" + e + ")");
            
            // GEOPOLY
            try {
                var res:Float = conn.request("SELECT geopoly_area('[[0,0],[1,0],[1,1],[0,1],[0,0]]') as val;").next().val;
                trace("GEOPOLY: SUCCESS (" + Std.string(res) + ")");
            } catch(e:Dynamic) trace("GEOPOLY: FAILED (" + e + ")");

            
            // Session / Preupdate Hook (Testing if pragmas or functions exist)
            try {
                // Preupdate hook is internal, but session extension uses it.
                // We can't easily test session extension from sys.db.Sqlite without more complex glue, 
                // but we can check if it's in compile_options.
                trace("Session Support: Check compile_options for ENABLE_SESSION");
            } catch(e:Dynamic) trace("Session: FAILED (" + e + ")");
            
            conn.close();
        } catch (e:Dynamic) {
            trace("CRITICAL ERROR: " + e);
        }
    }
}
