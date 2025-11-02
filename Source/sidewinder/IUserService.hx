package sidewinder;

import hx.injection.Service;

typedef User = {
  var id:Int;
  var name:String;
  var email:String;
}

interface IUserService extends Service  {
	@get("/users")
	public function getAll():Array<User>;

	@get("/users/:id")
	public function getById(id:Int):Null<User>;

    @get("/users/cached/:id")
	public function getByIdCached(id:Int):Null<User>;

	@post("/users")
	public function create(user:User):User;

	@put("/users/:id")
	public function update(id:Int, user:User):Bool;

	@delete("/users/:id")
	public function delete(id:Int):Bool;
}
