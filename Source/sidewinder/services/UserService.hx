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

    public function listUsers(?limit:Int, ?offset:Int):Array<User> {
        var actualLimit = limit != null ? limit : 100;
        var actualOffset = offset != null ? offset : 0;
        
        var params = new Map<String, Dynamic>();
        params.set("limit", actualLimit);
        params.set("offset", actualOffset);

        var result:Array<User> = [];
        var rs = db.read("SELECT id, display_name, email, permissions FROM users ORDER BY id ASC LIMIT @limit OFFSET @offset", params);
        while (rs.hasNext()) {
            result.push(mapRecordToUser(rs.next()));
        }
        return result;
    }

    private function mapRecordToUser(r:Dynamic):User {
        if (r == null) return null;
        var perms:Array<String> = [];
        if (r.permissions != null && r.permissions != "") {
            try {
                perms = haxe.Json.parse(r.permissions);
            } catch (e:Dynamic) {}
        }
        return { 
            id: r.id, 
            name: r.display_name, 
            email: r.email,
            permissions: perms
        };
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
        var rs = db.read("SELECT id, display_name, email, permissions FROM users WHERE id = @id", params);
        return mapRecordToUser(rs.next());
    }

    public function getByEmail(email:String):Null<User> {
        var params = new Map<String, Dynamic>();
        params.set("email", email);
        var rs = db.read("SELECT id, display_name, email, permissions FROM users WHERE email = @email", params);
        return mapRecordToUser(rs.next());
    }

    public function create(user:User):User {
        var params = new Map<String, Dynamic>();
        params.set("email", user.email);
        params.set("username", user.email);
        params.set("display_name", user.name);
        params.set("password_hash", "!");
        params.set("permissions", user.permissions != null ? haxe.Json.stringify(user.permissions) : "[]");
        
        sidewinder.logging.HybridLogger.debug('[UserService] Creating user: ' + user.email + ' (' + user.name + ')');
        var newId = db.executeAndGetId("INSERT INTO users (email, username, display_name, password_hash, permissions) VALUES (@email, @username, @display_name, @password_hash, @permissions)", params);
        user.id = newId;
        return user;
    }

    public function update(id:Int, user:User):Bool {
        var params = new Map<String, Dynamic>();
        params.set("id", id);
        params.set("display_name", user.name);
        params.set("email", user.email);
        params.set("permissions", user.permissions != null ? haxe.Json.stringify(user.permissions) : "[]");
        
        db.write("UPDATE users SET display_name = @display_name, email = @email, permissions = @permissions WHERE id = @id", params);
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
