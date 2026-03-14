package sidewinder.interfaces;

interface IUserServiceHandler {
	@requiresPermission("manage_users")
	@get("/users")
	public function listUsers(?limit:Int, ?offset:Int):Array<User>;

	@requiresPermission("manage_users")
	@get("/users/:id")
	public function getById(id:Int):Null<User>;

	@requiresPermission("manage_users")
    @get("/users/cached/:id")
	public function getByIdCached(id:Int):Null<User>;

	@requiresPermission("manage_users")
	@get("/users/by_email")
	public function getByEmail(email:String):Null<User>;

	@requiresPermission("manage_users")
	@post("/users")
	public function create(user:User):User;

	@requiresPermission("manage_users")
	@put("/users/:id")
	public function update(id:Int, user:User):Bool;

	@requiresPermission("manage_users")
	@delete("/users/:id")
	public function delete(id:Int):Bool;

	public function getUserIdByApiKey(apiKey:String):Null<Int>;
}
