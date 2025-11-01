package;

import IUserService;
import IUserService.User;
import Database;

class UserService implements IUserService {
    // Legacy in-memory list kept for backward compatibility of any code still referencing it
    // but create/update/delete now operate on the database.
    var users:Array<User> = [];

    public function new() {}

    public function getAll():Array<User> {
        var result:Array<User> = [];
        // Fetch rows from database
        var rs = Database.requestWithParams("SELECT id, display_name, email FROM users ORDER BY id ASC", null);
        while (rs.hasNext()) {
            var r = rs.next();
            result.push({ id: r.id, name: r.display_name, email: r.email });
        }
        return result;
    }

    public function getByIdCached(id:Int):Null<User> {
        var cacheKey = "user:" + id;
        var cache = DI.get(ICacheService);

        // Try cache first using getOrCompute (TTL 60s)
        var user:User = cache.getOrCompute(cacheKey, function() {
            return getById(id);
        }, 60000);

        return user;
    }

    public function getById(id:Int):Null<User> {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        var rs = Database.requestWithParams("SELECT id, display_name, email FROM users WHERE id = @id", params);
        var record = rs.next();
        if (record == null) return null;
        return { id: record.id, name: record.display_name, email: record.email };
    }

    public function create(user:User):User {
        var params = new Map<String, Dynamic>();
        params.set("email", user.email);
        // Use email as username if not provided (assumption)
        params.set("username", user.email);
        params.set("display_name", user.name);
        // Placeholder password hash since User typedef lacks password (assumption)
        params.set("password_hash", "!");
        var conn = Database.acquire();
        var insertSql = "INSERT INTO users (email, username, display_name, password_hash) VALUES (@email, @username, @display_name, @password_hash)";
        conn.request(Database.buildSql(insertSql, params));
        var rs = conn.request("SELECT last_insert_rowid() AS id");
        var rec = rs.next();
        Database.release(conn);
        if (rec == null) return user; // unexpected
        return { id: rec.id, name: user.name, email: user.email };
    }

    public function update(id:Int, user:User):Bool {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        params.set("display_name", user.name);
        params.set("email", user.email);
        var conn = Database.acquire();
        var updateSql = "UPDATE users SET display_name = @display_name, email = @email WHERE id = @id";
        conn.request(Database.buildSql(updateSql, params));
        // Check affected rows
        var rs = conn.request("SELECT changes() AS affected");
        var rec = rs.next();
        Database.release(conn);
        return rec != null && rec.affected > 0;
    }

    public function delete(id:Int):Bool {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        var conn = Database.acquire();
        var deleteSql = "DELETE FROM users WHERE id = @id";
        conn.request(Database.buildSql(deleteSql, params));
        var rs = conn.request("SELECT changes() AS affected");
        var rec = rs.next();
        Database.release(conn);
        return rec != null && rec.affected > 0;
    }
}
