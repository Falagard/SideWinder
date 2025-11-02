package sidewinder;

import sidewinder.Router.Middleware;
import sidewinder.Router.Handler;

class App {
  public static var router = SideWinderRequestHandler.router;

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
