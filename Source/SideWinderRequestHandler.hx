package;

import haxe.ds.StringMap;
import haxe.Json;
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

	function readBody():String {
		var len = Std.parseInt(headers.get("Content-Length"));
		if (len == null || len <= 0)
			return "";
		var bytes = haxe.io.Bytes.alloc(len);
		rfile.readFullBytes(bytes, 0, len);
		return bytes.toString();
	}

	function parseJsonFromBody(headers:StringMap<String>, body:String):Dynamic {
		var ct = headers.get("Content-Type");
		if (ct == null)
			return null;
		if (ct.indexOf("application/json") != -1) {
			try
				return Json.parse(body)
			catch (e:Dynamic)
				return null;
		}
		return null;
	}

	function parseFormFromBody(headers:StringMap<String>, body:String):StringMap<String> {
		var ct = headers.get("Content-Type");
		if (ct == null)
			return new StringMap<String>();
		var form = new StringMap<String>();
		if (ct.indexOf("application/x-www-form-urlencoded") != -1) {
			for (pair in body.split("&")) {
				var kv = pair.split("=");
				if (kv.length == 2) {
					form.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
				}
			}
		}
		return form;
	}

	// --- Request Handling ---
	// Override handleCommand to dispatch based on method
	// Read body and parse query parameters
	// Construct Request and Response objects
	// Find matching route and invoke handler

	override function handleCommand(method:String):Void {

        trace("handleCommand called at " + Sys.time());

		var pathOnly = this.path.split("?")[0];
		var match = router.find(method, pathOnly);
		if (match == null) {
			handleStatic();
			return;
		}

		var body = readBody();
		var query = parseQuery(this.path);
		var parsed = parseJsonFromBody(headers, body);
		var formBody = parseFormFromBody(headers, body);

		var req:Request = {
			method: method,
			path: pathOnly,
			headers: headers,
			query: query,
			body: body,
			jsonBody: parsed,
			formBody: formBody,
			params: match.params
		};

		var res:Response = {
			write: (s) -> wfile.writeString(s),
			setHeader: (k, v) -> sendHeader(k, v),
			sendError: (c) -> sendError(c),
			sendResponse: (r) -> sendResponse(r),
			endHeaders: () -> endHeaders(),
			end: () -> {}
		};

		try {
			router.handle(req, res, match.route);
		} catch (e:Dynamic) {
			sendError(snake.http.HTTPStatus.INTERNAL_SERVER_ERROR, "Internal Server Error");
			trace("Middleware/Handler error: " + Std.string(e));
		}

        trace("handleCommand completed at " + Sys.time());
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

	// --- REST API Setup ---
	override private function setup():Void {
		super.setup();
		serverVersion = 'SideWinder/0.0.1';
		//commandHandlers.set("POST", do_POST);
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
