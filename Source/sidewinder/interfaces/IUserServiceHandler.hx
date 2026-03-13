package sidewinder.interfaces;

interface IUserServiceHandler {
	@get("/users")
	public function listUsers(?limit:Int, ?offset:Int):Array<User>;

	@get("/users/:id")
	public function getById(id:Int):Null<User>;

    @get("/users/cached/:id")
	public function getByIdCached(id:Int):Null<User>;

	@get("/users/by_email")
	public function getByEmail(email:String):Null<User>;

	@post("/users")
	public function create(user:User):User;

	@put("/users/:id")
	public function update(id:Int, user:User):Bool;

	@delete("/users/:id")
	public function delete(id:Int):Bool;
}
