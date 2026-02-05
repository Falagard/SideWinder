package sidewinder;

import haxe.ds.StringMap;
import snake.http.*;

typedef Request = {
	var method:String;
	var path:String;
	var headers:Map<String, String>;
	var query:Map<String, String>;
	var params:Map<String, String>;
	var body:String;
	var jsonBody:Dynamic;
	var formBody:StringMap<String>;
	var cookies:StringMap<String>;
	var files:Array<UploadedFile>;
	var ?ip:String;
};

typedef UploadedFile = {
	var fieldName:String; // Form field name
	var fileName:String; // Original filename
	var filePath:String; // Saved path on server
	var contentType:String; // MIME type
	var size:Int; // File size in bytes
	@:optional var authContext:AuthContext;
};

typedef AuthContext = {
	var authenticated:Bool;
	var userId:Null<Int>;
	var session:Null<Dynamic>;
	var token:Null<String>;
};

typedef Response = {
	var write:(String) -> Void;
	var setHeader:(String, String) -> Void;
	var sendError:(HTTPStatus) -> Void;
	var sendResponse:(HTTPStatus) -> Void;
	var endHeaders:() -> Void;
	var end:() -> Void;
	var setCookie:(name:String, value:String, ?options:{
		path:String,
		domain:String,
		maxAge:String,
		httpOnly:Bool,
		secure:Bool
	}) -> Void;
};

class Route {
	public var method:String;
	public var pattern:String;
	public var regex:EReg;
	public var paramNames:Array<String>;
	public var handler:Handler;

	public function new(method:String, pattern:String, handler:Handler) {
		this.method = method;
		this.pattern = pattern;
		this.handler = handler;
		var parts = pattern.split("/");
		var reParts = [];
		paramNames = [];
		for (p in parts) {
			if (StringTools.startsWith(p, ":")) {
				paramNames.push(p.substr(1));
				reParts.push("([^/]+)");
			} else {
				reParts.push(EReg.escape(p));
			}
		}
		var patternRe = "^" + reParts.join("/") + "$";
		this.regex = new EReg(patternRe, "");
	}

	public function matches(path:String):Null<Map<String, String>> {
		if (!regex.match(path))
			return null;
		var params = new Map<String, String>();
		for (i in 0...paramNames.length) {
			params.set(paramNames[i], regex.matched(i + 1));
		}
		return params;
	}
}

typedef Middleware = (Request, Response, Void->Void) -> Void;
typedef Handler = Request->Response->Void;

typedef RouteResult = {
	route:Route,
	params:Map<String, String>
}

class Router {
	public var routes:Array<Route> = [];
	public var middleware:Array<Middleware> = [];

	public function new() {}

	public function add(method:String, pattern:String, handler:Handler):Void {
		routes.push(new Route(method, pattern, handler));
	}

	public function use(mw:Middleware):Void {
		middleware.push(mw);
	}

	public function find(method:String, path:String):Null<RouteResult> {
		for (route in routes) {
			if (route.method == method) {
				var params = route.matches(path);
				if (params != null) {
					return {route: route, params: params};
				}
			}
		}
		return null;
	}

	public function handle(req:Request, res:Response, route:Route) {
		return runMiddleware(0, req, res, route);
	}

	function runMiddleware(index:Int, req:Request, res:Response, route:Route) {
		if (index < middleware.length) {
			var mw = middleware[index];
			return mw(req, res, () -> runMiddleware(index + 1, req, res, route));
		} else {
			return route.handler(req, res);
		}
	}
}
