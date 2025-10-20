package;

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
	// maybe pathParams: Map<String, String> for dynamic segments
};

typedef Response = {
	var write:(String) -> Void;
	var setHeader:(String, String) -> Void;
	var sendError:(HTTPStatus) -> Void;
	var sendResponse:(HTTPStatus) -> Void;
	var endHeaders:() -> Void;
	var end:() -> Void;
	// maybe convenience methods: json(), sendFile(), etc
};

class Route {
	public var method:String;
	public var pattern:String;
	public var regex:EReg;
	public var paramNames:Array<String>;
	// public var handler: Request->Response->Void;
	public var handler:Handler;

	public function new(method:String, pattern:String, handler:Handler) {
		this.method = method;
		this.pattern = pattern;
		this.handler = handler;
		// build regex and paramNames
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
		// var m = regex.matched(0);
		var params = new Map<String, String>();
		for (i in 0...paramNames.length) {
			params.set(paramNames[i], regex.matched(i + 1));
		}
		return params;
	}
}

typedef Middleware = (Request, Response, Void->Void) -> Void;
typedef Handler = Request->Response->Void;

// typedef AsyncHandler = Request->Response->Future<Noise>;
// typedef AsyncMiddleware = (Request, Response, Void->Future<Noise>) -> Future<Noise>;

typedef RouteResult = {
	route:Route,
	params:Map<String, String>
}

class Router {
	public var routes:Array<Route> = [];
	public var middleware:Array<Middleware> = [];

	// public var middleware:Array<AsyncMiddleware> = [];

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
