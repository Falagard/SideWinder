package;

import hl.Bytes;
import snake.server.*;
import snake.socket.*;
import sys.net.Host;
import sys.net.Socket;
import sys.io.*;
import haxe.io.Path;
import snake.http.*;

import Router;

class SideWinderRequestHandler extends SimpleHTTPRequestHandler {

	public static var corsEnabled = false;
	public static var cacheEnabled = true;
	public static var silent = false;

	public static var router:Router = new Router();

	static function parseQuery(url:String):Map<String, String> {
		var result = new Map<String, String>();
		var idx = url.indexOf("?");
		if (idx == -1)
			return result;
		var query = url.substr(idx + 1);
		for (pair in query.split("&")) {
			var kv = pair.split("=");
			if (kv.length == 2)
				result.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
		}
		return result;
	}

	function dispatch(method:String):Void {
		var path = this.path; 
		var routeResult = SideWinderRequestHandler.router.find(method, path);
		if (routeResult != null) {
			// build Request, Response
			var req = {
				method: method,
				path: path,
				headers: this.headers,
				query: parseQuery(path),
				body: readRequestBodyIfAny()
			};
			var res = {
				write: (s) -> this.wfile.writeString(s),
				setHeader: (k, v) -> this.sendHeader(k, v),
				sendStatus: (code) -> this.sendError(code),
				end: () -> {}
			};
			routeResult.route.handler(req, res);
			// after handler returns, ensure response is flushed / connection closed
		} else {
			// fallback: static file 
			handleStatic();
		}
	}

	function handleStatic() {
		var url = this.path;
		if (StringTools.startsWith(url, "/static/")) {
			// Serve static files from CWD/static
			var staticDir = Path.addTrailingSlash(Sys.getCwd()) + "static";
			// Save old directory, set to staticDir for this request
			var oldDir = this.directory;
			this.directory = staticDir;
			// Remove /static prefix for file lookup
			this.path = url.substr("/static".length);
			// Use parent GET logic
			var handled = false;
			try {
				super.do_GET();
				handled = true;
			} catch (e:Dynamic) {
				// fallback to error below
			}
			this.directory = oldDir;
		}
	}
	
	function readRequestBodyIfAny():String {
		// if (this.command == "POST" || this.command == "PUT") {
		// 	var length = Std.parseInt(this.headers.get("Content-Length"));
		// 	if (length != null && length > 0) {
		// 		var buf = Bytes.alloc(length);
		// 		this.rfile.readBytes(buf, 0, length);
		// 		return buf.toString();
		// 	}
		// }
		return "";
	}

	// --- REST API Setup ---
	override private function setup():Void {
		super.setup();
		serverVersion = 'SideWinder/0.0.1';
		commandHandlers.set("POST", do_POST);
	}

	override private function do_GET():Void {
		dispatch("GET");
	}

	override private function do_HEAD():Void {
		dispatch("HEAD");
	}

	private function do_POST():Void {
		dispatch("POST");
	}

	// --- Utility: Send JSON ---
	private function sendJson(code:snake.http.HTTPStatus, obj:Dynamic) {
		var json = haxe.format.JsonPrinter.print(obj);

        sendResponse(code);
        sendHeader('Content-Type', 'application/json');
        endHeaders();

		wfile.writeString(json);
	}

	// --- WebSocket Broadcast (to be called from main server) ---
	public static var onStateChange:Void->Void = function() {};
	public static function broadcastState() {
		onStateChange(); // This will be set up in the main server file to broadcast via WebSocket
	}

	override public function endHeaders() {
		if (corsEnabled) {
			sendHeader('Access-Control-Allow-Origin', '*');
		}
		if (!cacheEnabled) {
			sendHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
		}
		super.endHeaders();
	}

	override private function logRequest(?code:Any, ?size:Any):Void {
		if (silent) {
			return;
		}
		super.logRequest(code, size);
	}

}