package;

import haxe.Timer;
import tink.core.Future;
import tink.core.Noise;
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
import tink.await.*;

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
		httpServer.threading = false;

		SideWinderRequestHandler.onStateChange = function() {
			//if we wanted to send out realtime updates via WebSocket here's where it would happen
		};

		// Example middleware: logging
		App.use(@await (req, res, next) -> {
			trace('${req.method} ${req.path}');
			next();
			return Future.sync(Noise);
		});

		// Example route: /hello
		App.get("/hello", @await (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Hello, world!");
			res.end();
			return Future.sync(Noise);
		});

		// New route: /goodbye
		App.get("/goodbye", @await (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Goodbye, world!");
			res.end();
			return Future.sync(Noise);
		});

		App.get("/private", @await (req, res) -> {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "text/plain");
			res.endHeaders();
			res.write("Private content accessed!");
			res.end();
			return Future.sync(Noise);
		});

		//App.get("/async", getAsync);

		// Example middleware: auth simulation
    	App.use(@await (req, res, next) -> {
			if (StringTools.startsWith(req.path, "/private")) {
				res.sendError(HTTPStatus.UNAUTHORIZED);
				res.setHeader("Content-Type", "text/plain");
				res.endHeaders();
				res.write("Unauthorized");
			} else next();
			return Future.sync(Noise);
		});


	}

	@async public function getAsync(req:Request, res:Response) {
		return @await getValue( "Hello from async function!", 1000 );
	}

	static function getValue( message:String, delay:Int ) {
		return Future.irreversible( callback -> Timer.delay(() -> callback( message ), delay ));
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




