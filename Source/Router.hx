package;

import snake.http.*;

typedef Request = {
    var method: String;
    var path: String;
    var headers: Map<String, String>;
    var query: Map<String, String>;
    var body: String; // or Bytes
  // maybe pathParams: Map<String, String> for dynamic segments
};

typedef Response = {
    var write: (String) -> Void;
    var setHeader: (String, String) -> Void;
    var sendStatus: (HTTPStatus) -> Void;
    var end: () -> Void;
  // maybe convenience methods: json(), sendFile(), etc
};

class Route {
  public var method:String;
  public var pattern:String;
  public var regex:EReg;
  public var paramNames:Array<String>;
  public var handler: Request->Response->Void;

  public function new(method:String, pattern:String, handler:Request->Response->Void) {
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
    if (!regex.match(path)) return null;
    //var m = regex.matched(0);
    var params = new Map<String, String>();
    for (i in 0...paramNames.length) {
      params.set(paramNames[i], regex.matched(i + 1));
    }
    return params;
  }
}



typedef Middleware = Request->Response->Void->Void; // (req, res, next)

typedef Handler = Request->Response->Void;

typedef RouteResult = {
  route:Route,
  params:Map<String,String>
}

class Router {
  public var routes:Array<Route>;


  public function new() {
    routes = [];
  }

  public function add(method:String, pattern:String, handler:Handler):Void {
    routes.push(new Route(method, pattern, handler));
  }

  public function find(method:String, path:String):Null<RouteResult> {
    for (route in routes) {
      if (route.method == method) {
        var params = route.matches(path);
        if (params != null) {
          return { route: route, params: params };
        }
      }
    }
    return null;
  }

  public function dispatch(req:Request, res:Response, route:Route):Void {
    // maybe call middleware, then route.handler
    route.handler(req, res);
  }
}
