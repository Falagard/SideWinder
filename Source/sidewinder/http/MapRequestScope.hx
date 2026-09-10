package sidewinder.http;

/**
 * Container-free `IRequestScope`: a plain attribute bag.
 *
 * This is what a lightweight application gets by default, and it is why a
 * SideWinder route can now execute with no hx-injection container and no
 * `ProjectContext` anywhere in the program.
 */
class MapRequestScope implements IRequestScope {
	public var requestId(default, null):String;

	final attributes = new Map<String, Dynamic>();

	public function new(requestId:String) {
		this.requestId = requestId;
	}

	public function setAttribute(key:String, value:Dynamic):Void {
		attributes.set(key, value);
	}

	public function getAttribute(key:String):Null<Dynamic> {
		return attributes.get(key);
	}

	public function unwrap():Null<Dynamic> {
		return null;
	}

	public function dispose():Void {
		attributes.clear();
	}
}
