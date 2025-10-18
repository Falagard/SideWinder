package;

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
		httpServer.threading = false;

		SideWinderRequestHandler.onStateChange = function() {
			//if we wanted to send out realtime updates via WebSocket here's where it would happen
		};

		SideWinderRequestHandler.router.add("GET", "/hello", (req, res) -> {
			res.setHeader("Content-Type", "text/plain");
			res.write("Hello, world!");
			res.end();
			});
	}

	public static function get(path:String, handler:Request->Response->Void):Void {
    	router.add("GET", path, handler);
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




