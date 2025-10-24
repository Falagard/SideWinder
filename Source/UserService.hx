package;

import IUserService;
import IUserService.User;

@transient
class UserService implements IUserService {
    var users:Array<User> = [];

    public function new() {}

    public function getAll():Array<User> {
        return users;
    }

    public function getById(id:Int):Null<User> {
        for (u in users) if (u.id == id) return u;
        return null;
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
