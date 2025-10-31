package;

import IUserService;
import IUserService.User;

class UserService implements IUserService {
    var users:Array<User> = [];

    public function new() {}

    public function getAll():Array<User> {
        return users;
    }

    public function getById(id:Int):Null<User> {
        var cacheKey = "user:" + id;
        var cache = DI.get(ICacheService);

        // Try cache first using getOrCompute (TTL 60s)
        var user:User = cache.getOrCompute(cacheKey, function() {
            var conn = Database.acquire();
            var sql = "SELECT * FROM users WHERE id = " + Std.string(id) + ";";
            var rs = conn.request(sql);
            var record = rs.next();
            Database.release(conn);
            if (record == null) return null;
            return { id: record.id, name: record.display_name, email: record.email };
        }, 60000);

        return user;
    }

    public function create(user:User):User {
        users.push(user);
        return user;
    }

    public function update(id:Int, user:User):Bool {
        for (i in 0...users.length) {
            if (users[i].id == id) {
                users[i] = user;
                return true;
            }
        }
        return false;
    }

    public function delete(id:Int):Bool {
        for (i in 0...users.length) {
            if (users[i].id == id) {
                users.splice(i, 1);
                return true;
            }
        }
        return false;
    }
}
