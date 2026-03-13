package sidewinder.services;

import sidewinder.interfaces.IUserService;
import sidewinder.interfaces.User;
import sidewinder.interfaces.IDatabaseService;
import sidewinder.interfaces.ICacheService;

import hx.injection.Service;
import sidewinder.core.DI;

class UserService implements IUserService implements Service {
	public function getConstructorArgs():Array<String> {
		return [];
	}

    var users:Array<User> = [];
    var db:IDatabaseService;

    public function new() {
        db = DI.get(IDatabaseService);
    }

    public function getAll():Array<User> {
        var result:Array<User> = [];
        var rs = db.read("SELECT id, display_name, email FROM users ORDER BY id ASC", null);
        while (rs.hasNext()) {
            var r = rs.next();
            result.push({ id: r.id, name: r.display_name, email: r.email });
        }
        return result;
    }

    public function getByIdCached(id:Int):Null<User> {
        var cacheKey = "user:" + id;
        var cache = DI.get(ICacheService);
        var user:User = cache.getOrCompute(cacheKey, function() {
            return getById(id);
        }, 60000);
        return user;
    }

    public function getById(id:Int):Null<User> {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        var rs = db.read("SELECT id, display_name, email FROM users WHERE id = @id", params);
        var record = rs.next();
        if (record == null) return null;
        return { id: record.id, name: record.display_name, email: record.email };
    }

    public function create(user:User):User {
        var params = new Map<String, Dynamic>();
        params.set("email", user.email);
        params.set("username", user.email);
        params.set("display_name", user.name);
        params.set("password_hash", "!");
        
        sidewinder.logging.HybridLogger.debug('[UserService] Creating user: ' + user.email + ' (' + user.name + ')');
        var newId = db.executeAndGetId("INSERT INTO users (email, username, display_name, password_hash) VALUES (@email, @username, @display_name, @password_hash)", params);
        return { id: newId, name: user.name, email: user.email };
    }

    public function update(id:Int, user:User):Bool {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        params.set("display_name", user.name);
        params.set("email", user.email);
        
        db.write("UPDATE users SET display_name = @display_name, email = @email WHERE id = @id", params);
        var rs = db.read("SELECT changes() AS affected");
        var rec = rs.next();
        
        return rec != null && rec.affected > 0;
    }

    public function delete(id:Int):Bool {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        
        db.write("DELETE FROM users WHERE id = @id", params);
        var rs = db.read("SELECT changes() AS affected");
        var rec = rs.next();
        
        return rec != null && rec.affected > 0;
    }
}
