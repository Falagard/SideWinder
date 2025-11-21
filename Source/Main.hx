// Legacy duplicate file. Implementation moved to sidewinder/Main.hx.


import hx.injection.ServiceCollection;
import haxe.Json;
import haxe.Http;
import haxe.Timer;
import sidewinder.Router.Response;
import sidewinder.Router.Request;
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
import sidewinder.Database;
import hx.injection.Service;
import sidewinder.*;

using hx.injection.ServiceExtensions;

class Main extends Application {
	private static final DEFAULT_PROTOCOL = "HTTP/1.0"; // snake-server needs more work for 1.1 connections
	private static final DEFAULT_ADDRESS = "127.0.0.1";
	private static final DEFAULT_PORT = 8000;

	private var httpServer:SideWinderServer;

	public static var router = SideWinderRequestHandler.router;

	public var cache:ICacheService;

	public function new() {
		super();

		// Initialize database and run migrations
		Database.runMigrations();
		HybridLogger.init(true, HybridLogger.LogLevel.DEBUG);

		// Cache service will be resolved from DI

		var directory:String = null;

		// Configure SideWinderRequestHandler
		BaseHTTPRequestHandler.protocolVersion = DEFAULT_PROTOCOL;
		SideWinderRequestHandler.corsEnabled = false;
		SideWinderRequestHandler.cacheEnabled = true;
		SideWinderRequestHandler.silent = true;

		DI.init(c -> {
			c.addScoped(IUserService, UserService);
			c.addSingleton(ICacheService, CacheService);
		});

		cache = DI.get(ICacheService);
		
		// Create singleton cookieJar for all async clients
		var cookieJar:ICookieJar = new CookieJar();

		httpServer = new SideWinderServer(new Host(DEFAULT_ADDRESS), DEFAULT_PORT, SideWinderRequestHandler, true, directory);

		AutoRouter.build(router, IUserService, function() {
			return DI.get(IUserService);
		});

		// Synchronous AutoClient example (legacy port 8080 kept for reference; server actually runs on DEFAULT_PORT)
		var userClient:IUserService = AutoClient.create(IUserService, "http://localhost:8080");

		// AutoClientAsync example: create async client pointed at the active server port and perform calls.
		// Each interface method getAll() becomes getAllAsync(onSuccess, onFailure).
		var userClientAsync = AutoClientAsync.create(IUserService, 'http://' + DEFAULT_ADDRESS + ':' + DEFAULT_PORT, cookieJar);

		// Delay invocation slightly to allow server startup.
		Timer.delay(() -> {
			userClientAsync.getAllAsync(function(users:Array<IUserService.User>) {
				HybridLogger.debug('AutoClientAsync getAll returned ' + (users == null ? 0 : users.length) + ' users');
			}, function(err:Dynamic) {
				HybridLogger.error('AutoClientAsync getAll failed: ' + Std.string(err));
			});
		}, 100);

		// Demonstrate createAsync + deleteAsync to verify DELETE handling (raw socket implementation in AutoClientAsync for DELETE).
		Timer.delay(() -> {
			userClientAsync.createAsync({ id: 0, name: 'TempUser', email: 'tempuser@example.com' }, function(newUser:IUserService.User) {
				HybridLogger.debug('AutoClientAsync create returned id=' + newUser.id);
				userClientAsync.deleteAsync(newUser.id, function(result:Bool) {
					HybridLogger.debug('AutoClientAsync delete returned ' + result + ' for id=' + newUser.id);
				}, function(err:Dynamic) {
					HybridLogger.error('AutoClientAsync delete failed: ' + Std.string(err));
				});
			}, function(err:Dynamic) {
				HybridLogger.error('AutoClientAsync create failed: ' + Std.string(err));
			});
		}, 300);

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
			} else
				next();
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

		App.get("/async", (req, res) -> {
			// Requests run in their own thread, so we can block here.
			// In fact, async operations must block the request thread to avoid issues, because otherwise the request may finish before the async operation completes.

			// Simulate an asynchronous operation using AsyncBlockerPool, create a new thread aysncOperationSimulation which takes some time to complete and then calls the cb
			// callback with the result
			var html = AsyncBlockerPool.run(cb -> {
				// do some async work, call cb when done
				Thread.create(() -> {
					asyncOperationSimulation(function(result:String) {
						cb(result);
					}, function() {
						// failure callback simulation
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

		// comment this out to simulate success
		return onSuccess("<html><body><p>This response was generated after a simulated async operation.</p></body></html>");

		// uncomment below to simulate failure
		// onFailure();
	}

	// Entry point
	public static function main() {
		var app:Main = new Main();
		app.exec();
	}

	// Override update to serve HTTP requests
	public override function update(deltaTime:Int):Void {
		httpServer.handleRequest();
	}

	// Override createWindow to prevent Lime from creating a window
	override public function createWindow(attributes:WindowAttributes):Window {
		return null;
	}
}
