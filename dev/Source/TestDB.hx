import sidewinder.services.SqliteDatabaseService;
import sidewinder.interfaces.User;

class TestDB {
    static function main() {
        var db = new SqliteDatabaseService();
        
        // Initial setup
        try {
            db.execute("CREATE TABLE IF NOT EXISTS test_users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);");
        } catch(e:Dynamic) {
            trace("Table already exists or error: " + e);
        }

        var params = new Map<String, Dynamic>();
        params.set("name", "Test User");
        
        var id = db.executeAndGetId("INSERT INTO test_users (name) VALUES (@name)", params);
        trace("Inserted ID: " + id);
        
        if (id == 0) {
            trace("FAILURE: ID was 0");
        } else {
            trace("SUCCESS: ID was " + id);
        }

        Sys.exit(id == 0 ? 1 : 0);
    }
}
