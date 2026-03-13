package sidewinder.controllers;

import sidewinder.interfaces.IUserService;
import sidewinder.interfaces.User;
import snake.http.HTTPStatus;

interface IAdminService extends hx.injection.Service {
    @get("/admin/users")
    @requiresPermission("manage_users")
    public function listAllUsers():Array<User>;

    @post("/admin/promote")
    @requiresPermission("admin")
    public function promoteToAdmin(userId:Int):Bool;
}

class AdminController implements IAdminService {
    var userService:IUserService;

    public function new(userService:IUserService) {
        this.userService = userService;
    }

    public function listAllUsers():Array<User> {
        return userService.listUsers(100, 0);
    }

    public function promoteToAdmin(userId:Int):Bool {
        var user = userService.getById(userId);
        if (user == null) return false;
        
        if (user.permissions == null) user.permissions = [];
        if (user.permissions.indexOf("admin") == -1) {
            user.permissions.push("admin");
        }
        return userService.update(userId, user);
    }
}
