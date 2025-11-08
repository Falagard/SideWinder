package sidewinder;

import haxe.ds.StringMap;
import haxe.Json;
import snake.server.*;
import snake.socket.*;
import sys.net.Host;
import sys.net.Socket;
import sys.io.*;
import haxe.io.Path;
import snake.http.*;
import sidewinder.Router;

class SideWinderRequestHandler extends SimpleHTTPRequestHandler {
	static function parseCookies(header:String):StringMap<String> {
		var cookies = new StringMap<String>();
		if (header == null) return cookies;
		for (pair in header.split(";")) {
			var kv = pair.split("=");
			if (kv.length == 2) {
				cookies.set(StringTools.trim(kv[0]), StringTools.trim(kv[1]));
			}
		}
		return cookies;
	}
	public static var corsEnabled = false;
	public static var cacheEnabled = true;
	public static var silent = false;
    private var currentSessionId:String = null;
	private var isServingStatic:Bool = false;
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

	override function handleCommand(method:String):Void {
		var pathOnly = this.path.split("?")[0];
		// Handle OPTIONS preflight request
		if (method == "OPTIONS") {
			sendResponse(snake.http.HTTPStatus.OK);
			sendHeader('Access-Control-Allow-Origin', '*'); // Change port as needed
			sendHeader('Access-Control-Allow-Credentials', 'true'); // Remove if not using cookies/auth
			sendHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
			sendHeader('Access-Control-Allow-Headers', 'Content-Type, Accept, Authorization, X-Requested-With');
			sendHeader('Vary', 'Origin');
			endHeaders();
			wfile.writeString("");
			return;
		}

		var match = router.find(method, pathOnly);
		if (match == null) {
			handleStatic();
			return;
		}

		var body = readBody();
		var query = parseQuery(this.path);
		var parsed = parseJsonFromBody(headers, body);
		var formBody = parseFormFromBody(headers, body);

		var cookies = parseCookies(headers.get("Cookie"));
		var sessionId = cookies.get("session_id");
		if (sessionId == null) {
			sessionId = Std.string(Math.floor(Math.random() * 1000000000)) + "_" + Std.string(Sys.time());
			cookies.set("session_id", sessionId);
			currentSessionId = sessionId;
		}

		var req:Request = {
			method: method,
			path: pathOnly,
			headers: headers,
			query: query,
			body: body,
			jsonBody: parsed,
			formBody: formBody,
			params: match.params,
			cookies: cookies
		};

		var res:Response = {
			write: (s) -> wfile.writeString(s),
			setHeader: (k, v) -> sendHeader(k, v),
			sendError: (c) -> sendError(c),
			sendResponse: (r) -> sendResponse(r),
			endHeaders: () -> endHeaders(),
			end: () -> wfile.flush(),
			setCookie: function(name:String, value:String, ?options:{path:String, domain:String, maxAge:String, httpOnly:Bool, secure:Bool}) {
				var cookie = name + "=" + value;
				if (options != null) {
					if (options.path != null) cookie += "; Path=" + options.path;
					if (options.domain != null) cookie += "; Domain=" + options.domain;
					if (options.maxAge != null) cookie += "; Max-Age=" + options.maxAge;
					if (options.httpOnly) cookie += "; HttpOnly";
					if (options.secure) cookie += "; Secure";
				}
				sendHeader("Set-Cookie", cookie);
			}
		};

		try {
			router.handle(req, res, match.route);
		} catch (e:Dynamic) {
			sendError(snake.http.HTTPStatus.INTERNAL_SERVER_ERROR, "Internal Server Error");
			trace("Middleware/Handler error: " + Std.string(e));
		}
	}

	function handleStatic() {
		var url = this.path;
		if (StringTools.startsWith(url, "/static/")) {
			var staticDir = Path.addTrailingSlash(Sys.getCwd()) + "static";
			var oldDir = this.directory;
			this.directory = staticDir;
			this.path = url.substr("/static".length);
			this.isServingStatic = true;
			var handled = false;
			try {
				super.do_GET();
				handled = true;
			} catch (e:Dynamic) {
			}
			this.isServingStatic = false;
			this.directory = oldDir;
		}
	}

	override private function setup():Void {
        super.setup();
		serverVersion = 'SideWinder/0.0.1';
	}

	private function sendJson(code:snake.http.HTTPStatus, obj:Dynamic) {
		var json = haxe.format.JsonPrinter.print(obj);

		sendResponse(code);
		sendHeader('Content-Type', 'application/json');
		endHeaders();

		wfile.writeString(json);
	}

	public static var onStateChange:Void->Void = function() {};

	public static function broadcastState() {
		onStateChange();
	}

	override public function endHeaders() {
		// Skip adding extra headers when serving static files to avoid Content-Length mismatch
		if (isServingStatic) {
			super.endHeaders();
			return;
		}
		
		// Always set CORS headers for all responses
		sendHeader('Access-Control-Allow-Origin', 'http://localhost:3000'); // Change port as needed
		sendHeader('Access-Control-Allow-Credentials', 'true'); // Remove if not using cookies/auth
		sendHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
		sendHeader('Access-Control-Allow-Headers', 'Content-Type, Accept, Authorization, X-Requested-With');
		sendHeader('Vary', 'Origin');
		if (!cacheEnabled) {
			sendHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
		}
		if(currentSessionId != null) {
			sendHeader("Set-Cookie", "session_id=" + currentSessionId + "; Path=/; HttpOnly");
		}

		super.endHeaders();
	}

    override private function logMessage(message:String):Void {
        if (silent) {
			return;
		}

		super.logMessage(message);
	}
}
