package;

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
	private static final DEFAULT_PROTOCOL = "HTTP/1.0";
	private static final DEFAULT_ADDRESS = "127.0.0.1";
	private static final DEFAULT_PORT = 8000;

	private var httpServer:SideWinderServer;
	public static var router = SideWinderRequestHandler.router;

	public function new()
	{
		super();

		var directory:String = null;

		BaseHTTPRequestHandler.protocolVersion = DEFAULT_PROTOCOL;
		SideWinderRequestHandler.corsEnabled = false;
		SideWinderRequestHandler.cacheEnabled = true;
		SideWinderRequestHandler.silent = false;

		httpServer = new SideWinderServer(new Host(DEFAULT_ADDRESS), DEFAULT_PORT, SideWinderRequestHandler, true, directory);
		httpServer.threading = true;

		SideWinderRequestHandler.onStateChange = function() {
			//if we wanted to send out realtime updates via WebSocket here's where it would happen
		};

		// Example middleware: logging
		App.use((req, res, next) -> {
			trace('${req.method} ${req.path}');
			next();
		});

		// Example route: /hello
		App.get("/hello", (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Hello, world!");
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

		App.get("/async", (req, res) -> {

			// Requests run in their own thread, so we can block here. 
			// In fact, async operations must block the request thread to avoid issues, because otherwise the request may finish before the async operation completes.

			var currentTime = Date.now().toString();
			trace("Starting async operation at " + currentTime);

			// Simulate an asynchronous operation using AsyncBlockerPool
			var html = AsyncBlockerPool.run(cb -> {
				Sys.sleep(5); // Simulate a blocking operation, e.g., network call
				cb("<html><body><h1>Asynchronous Response</h1><p>" + currentTime + "</p><p>This response was generated after a simulated async operation.</p></body></html>");
			});
			
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/html");
			res.endHeaders();
			res.write(html);
			res.end();

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


	}
  	
	public static function main() {
		var app:Main = new Main();
		app.exec();
	}

	public override function update(deltaTime:Int):Void
	{
		httpServer.serve(0);
	}

	override public function createWindow(attributes:WindowAttributes): Window {
		trace("Hello Headless World");
		return null;
	}
}




