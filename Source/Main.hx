package;

import haxe.Json;
import haxe.Http;
import haxe.Timer;
import Router.Response;
import Router.Request;
import sys.thread.Thread;
import lime.app.Application;
import lime.ui.WindowAttributes;
import lime.ui.Window;
import snake.http.*;
import snake.socket.*;
import sys.net.Host;
import sys.net.Socket;
import snake.server.*;
import lime.ui.Gamepad;
import lime.ui.GamepadButton;
import Date;

class Main extends Application
{
	private static final DEFAULT_PROTOCOL = "HTTP/1.0"; //snake-server needs more work for 1.1 connections
	private static final DEFAULT_ADDRESS = "127.0.0.1";
	private static final DEFAULT_PORT = 8000;

	private var httpServer:SideWinderServer;
	public static var router = SideWinderRequestHandler.router;
    public var cache:Cache; 

	public function new()
	{
		super();

        cache = new Cache(1024); // Example cache with max 1024 entries

		var directory:String = null;

        // Configure SideWinderRequestHandler
		BaseHTTPRequestHandler.protocolVersion = DEFAULT_PROTOCOL;
		SideWinderRequestHandler.corsEnabled = false;
		SideWinderRequestHandler.cacheEnabled = true;
		SideWinderRequestHandler.silent = true;

		httpServer = new SideWinderServer(new Host(DEFAULT_ADDRESS), DEFAULT_PORT, SideWinderRequestHandler, true, directory);

		// Example middleware: logging
		//App.use((req, res, next) -> {
			//trace('${req.method} ${req.path} ' + Sys.time());
			//next();
		//});

        // Example middleware: auth simulation
    	App.use((req, res, next) -> {
			if (StringTools.startsWith(req.path, "/private")) {
				res.sendError(HTTPStatus.UNAUTHORIZED);
				res.setHeader("Content-Type", "text/plain");
				res.endHeaders();
				res.write("Unauthorized");
			} else next();
		});

		// Example route: /hello
		App.get("/hello", (req, res) -> {
            var html = "Hello, world!" + Sys.time();
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
            res.setHeader('Content-Length', Std.string(html.length));
			res.endHeaders();
			res.write(html);
			res.end();
		});

		// New route: /goodbye
		App.get("/goodbye", (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Goodbye, world!");
			res.end();
		});

		App.get("/private", (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Private content accessed!");
			res.end();
		});

		App.get("/users/:id", (req, res) -> {
            //req.params stores the dynamic segments from the URL pattern
			var id = req.params.get("id");

            var user = cache.getOrCompute("user:" + id, function() {
                trace('Loading user ' + id);
                return { id: id, name: "Alice", email: "alice@example.com" };
            }, 60000); // cache 60s


			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			var content = Json.stringify(user);
			res.write(content);
			res.end();
		});

		App.get("/async", (req, res) -> {

			// Requests run in their own thread, so we can block here. 
			// In fact, async operations must block the request thread to avoid issues, because otherwise the request may finish before the async operation completes.

    		// Simulate an asynchronous operation using AsyncBlockerPool, create a new thread aysncOperationSimulation which takes some time to complete and then calls the cb 
            // callback with the result
			var html = AsyncBlockerPool.run(cb -> {
                //do some async work, call cb when done 
				Thread.create(() -> {
					asyncOperationSimulation( function(result:String) {
                        cb(result);
                    }, function() {
                        cb("failed");
                    });
				});
			});
			
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/html");
			res.endHeaders();
			res.write(html);
			res.end();

		});

	}

    private function asyncOperationSimulation(onSuccess:(String) -> Void, onFailure:() -> Void):Void {
        // Simulate a long-running operation
        Sys.sleep(3);
        onSuccess("<html><body><p>This response was generated after a simulated async operation.</p></body></html>");
    }
  	
    // Entry point
	public static function main() {    
        
        #if hl
		//hl.Gc.flags = hl.Gc.flags | hl.Gc.GcFlag.NoThreads;
        #end
        
		var app:Main = new Main();
		app.exec();
	}

    // Override update to serve HTTP requests
	public override function update(deltaTime:Int):Void
	{
        //trace("update start at " + Sys.time());
        var start = Sys.time();
		httpServer.handleRequest();
        if(httpServer.requestHandled) {
            var end = Sys.time();
            trace("Request handled in " + (end - start) + " seconds");
        }
	}

    // Override createWindow to prevent Lime from creating a window
	override public function createWindow(attributes:WindowAttributes): Window {
	    return null;
	}
}




