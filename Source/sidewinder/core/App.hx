package sidewinder.core;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;

import sidewinder.routing.Router.Middleware;
import sidewinder.routing.Router.Handler;

class App {
  public static var router = sidewinder.routing.Router.instance;

  public static function get(path:String, handler:Handler):Void
    router.add("GET", path, handler);

  public static function post(path:String, handler:Handler):Void
    router.add("POST", path, handler);

  public static function put(path:String, handler:Handler):Void
    router.add("PUT", path, handler);

  public static function delete(path:String, handler:Handler):Void
    router.add("DELETE", path, handler);

  public static function use(mw:Middleware):Void
    router.use(mw);
}
