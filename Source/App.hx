package;

import Router.Middleware;
import Router.Handler;
import tink.core.Future;
import Router.AsyncHandler;
import Router.AsyncMiddleware;  


class App {
  public static var router = SideWinderRequestHandler.router;

  public static function get(path:String, handler:AsyncHandler):Void
    router.add("GET", path, handler);

  public static function post(path:String, handler:AsyncHandler):Void
    router.add("POST", path, handler);

  public static function put(path:String, handler:AsyncHandler):Void
    router.add("PUT", path, handler);

  public static function delete(path:String, handler:AsyncHandler):Void
    router.add("DELETE", path, handler);

  public static function use(mw:AsyncMiddleware):Void
    router.use(mw);
}
