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
import Database;

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

        // Initialize database and run migrations 
        Database.runMigrations();
        HybridLogger.init(true, HybridLogger.LogLevel.DEBUG);

        cache = new Cache(1024); // Example cache with max 1024 entries

		var directory:String = null;

        // Configure SideWinderRequestHandler
		BaseHTTPRequestHandler.protocolVersion = DEFAULT_PROTOCOL;
		SideWinderRequestHandler.corsEnabled = false;
		SideWinderRequestHandler.cacheEnabled = true;
		SideWinderRequestHandler.silent = true;

		httpServer = new SideWinderServer(new Host(DEFAULT_ADDRESS), DEFAULT_PORT, SideWinderRequestHandler, true, directory);

        // var userService = new UserService(); // or from Container.build() if using DI

        // var services = [
        //     { iface: IUserService, impl: userService }
        // ];

        //AutoRouter.build(router, services);

		// Example middleware: logging
		App.use((req, res, next) -> {
            // 
			HybridLogger.info('${req.method} ${req.path} ' + Sys.time());
			next();
		});

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

        App.get("/cookie", (req, res) -> {
            // Read a cookie from the request
            var sessionId = req.cookies.get("session_id");
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write(sessionId != null ? "Cookie: " + sessionId : "No session_id cookie found");
			res.end();
        });

		App.get("/users/:id", (req, res) -> {
            //req.params stores the dynamic segments from the URL pattern
			var id = req.params.get("id");

            // Use cache to get user data - the function will only be called if the item is not in the cache or has expired
            var cacheKey = "user:" + id;
            var user = cache.getOrCompute(cacheKey, function() {

                // Acquire a database connection
                var conn = Database.acquire();

                // Fetch user data from the database
                var sql = "SELECT * FROM users WHERE id = " + Std.string(id) + ";";
                var rs = conn.request(sql);
                // Get the first record
                var record = rs.next();
                // Release the connection back to the pool
                Database.release(conn);

                if (record == null) {
                    return {
                        success: false,
                        message: "User not found",
                        data: null
                    }
                }

                return {
                    success: true,
                    message: "",
                    data: {
                        id: record.id,
                        email: record.email,
                        username: record.username,
                        display_name: record.display_name,
                        bio: record.bio,
                        password_hash: record.password_hash,
                        avatar_path: record.avatar_path,
                        created_at: record.created_at
                    }
                };
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
                        //failure callback simulation
                        cb("<html><body><p>Async operation failed.</p></body></html>");
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
        
        //comment this out to simulate success
        return onSuccess("<html><body><p>This response was generated after a simulated async operation.</p></body></html>");

        //uncomment below to simulate failure
        //onFailure();
    }
  	
    // Entry point
	public static function main() {    
		var app:Main = new Main();
		app.exec();
	}

    // Override update to serve HTTP requests
	public override function update(deltaTime:Int):Void
	{
		httpServer.handleRequest();
	}

    // Override createWindow to prevent Lime from creating a window
	override public function createWindow(attributes:WindowAttributes): Window {
	    return null;
	}
}




