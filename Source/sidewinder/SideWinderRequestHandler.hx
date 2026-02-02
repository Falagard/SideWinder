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
	public var allowOrigin:String = "*";

	// Override sendHead to add cache headers for static files
	override private function sendHead():haxe.io.Input {
		var translatedPath = this.translatePath(this.path);
		var f:sys.io.FileInput = null;
		if (sys.FileSystem.exists(translatedPath) && sys.FileSystem.isDirectory(translatedPath)) {
			if (!StringTools.endsWith(translatedPath, "/")) {
				sendResponse(snake.http.HTTPStatus.MOVED_PERMANENTLY);
				var newURL = translatedPath.substr(0, translatedPath.length - 1);
				sendHeader("Location", newURL);
				sendHeader("Content-Length", "0");
				endHeaders();
				return null;
			}
			// Directory listing not supported, fallback to error
			sendError(snake.http.HTTPStatus.NOT_FOUND, "File not found");
			return null;
		}
		var ctype = guessType(translatedPath);
		if (StringTools.endsWith(translatedPath, "/")) {
			sendError(snake.http.HTTPStatus.NOT_FOUND, "File not found");
			return null;
		}
		try {
			f = sys.io.File.read(translatedPath, true);
		} catch (e:Dynamic) {
			sendError(snake.http.HTTPStatus.NOT_FOUND, "File not found");
			return null;
		}
		try {
			var fs = sys.FileSystem.stat(translatedPath);
			sendResponse(snake.http.HTTPStatus.OK);
			sendHeader("Content-type", ctype);
			sendHeader("Content-Length", Std.string(fs.size));
			sendHeader("Last-Modified", dateTimeString(fs.mtime));
			if (isServingStatic) {
				// 4 hours = 14400 seconds
				sendHeader('Cache-Control', 'public, max-age=14400, s-maxage=14400, must-revalidate, proxy-revalidate, immutable');
				var expiresUtc = Date.fromTime(Date.now().getTime() + 14400 * 1000);
				sendHeader('Expires', SideWinderRequestHandler.formatUtcRfc1123(expiresUtc));
			}
			endHeaders();
			return f;
		} catch (e:Dynamic) {
			f.close();
			throw e;
		}
	}

	// Helper to format Date as RFC 1123 UTC string
	public static function formatUtcRfc1123(date:Date):String {
		var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
		var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
		var d = date;
		var utcYear = d.getUTCFullYear();
		var utcMonth = d.getUTCMonth();
		var utcDate = d.getUTCDate();
		var utcDay = d.getUTCDay();
		var utcHours = d.getUTCHours();
		var utcMinutes = d.getUTCMinutes();
		var utcSeconds = d.getUTCSeconds();
		return days[utcDay] + ", " + (utcDate < 10 ? "0" : "") + utcDate + " " + months[utcMonth] + " " + utcYear + " " +
			(utcHours < 10 ? "0" : "") + utcHours + ":" + (utcMinutes < 10 ? "0" : "") + utcMinutes + ":" + (utcSeconds < 10 ? "0" : "") + utcSeconds + " GMT";
	}

		// Add constructor to accept allowOrigin
		public function new(request:Socket, clientAddress:{host:Host, port:Int}, server:BaseServer, ?directory:String, ?allowOrigin:String) {
			super(request, clientAddress, server, directory);
			if (allowOrigin != null) this.allowOrigin = allowOrigin;
		}

		static function parseCookies(header:String):StringMap<String> {
		var cookies = new StringMap<String>();
		if (header == null)
			return cookies;
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
		
		// Parse multipart/form-data for file uploads
		var files:Array<UploadedFile> = [];
		var ct = headers.get("Content-Type");
		if (ct != null && ct.indexOf("multipart/form-data") != -1) {
			var multipartData = MultipartParser.parseMultipart(body, ct);
			files = multipartData.files;
			// Merge multipart form fields into formBody
			for (key in multipartData.fields.keys()) {
				formBody.set(key, multipartData.fields.get(key));
			}
		}

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
			cookies: cookies,
			files: files,
			ip: clientAddress.host.toString()
		};

		var res:Response = {
			write: (s) -> wfile.writeString(s),
			setHeader: (k, v) -> sendHeader(k, v),
			sendError: (c) -> sendError(c),
			sendResponse: (r) -> sendResponse(r),
			endHeaders: () -> endHeaders(),
			end: () -> wfile.flush(),
			setCookie: function(name:String, value:String, ?options:{
				path:String,
				domain:String,
				maxAge:String,
				httpOnly:Bool,
				secure:Bool
			}) {
				var cookie = name + "=" + value;
				if (options != null) {
					if (options.path != null)
						cookie += "; Path=" + options.path;
					if (options.domain != null)
						cookie += "; Domain=" + options.domain;
					if (options.maxAge != null)
						cookie += "; Max-Age=" + options.maxAge;
					if (options.httpOnly)
						cookie += "; HttpOnly";
					if (options.secure)
						cookie += "; Secure";
				}
				sendHeader("Set-Cookie", cookie);
			}
		};

		try {
			// If using SnakeServerAdapter, enqueue instead of processing directly
			if (SnakeServerAdapter.instance != null) {
				SnakeServerAdapter.instance.enqueueRequest(req, res, match.route);
				// Send immediate response acknowledging receipt
				sendResponse(snake.http.HTTPStatus.ACCEPTED); // 202 Accepted
				sendHeader("Content-Type", "text/plain");
				endHeaders();
				wfile.writeString("Request queued for processing");
			} else {
				// Direct processing (fallback for non-adapter usage)
				router.handle(req, res, match.route);
			}
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
			var oldPath = this.path;
			this.directory = staticDir;
			this.path = url.substr("/static".length);
			this.isServingStatic = true;

			try {
				super.do_GET();
			} catch (e:haxe.io.Error) {
				if (e.match(Blocked)) {
					// Retry with blocking allowed
					trace("Retrying static file with blocking I/O");
					super.do_GET();
				} else {
					trace("Error serving static file: " + e);
				}
			} catch (e:Dynamic) {
				trace("Error serving static file: " + e);
			}
			this.isServingStatic = false;
			this.directory = oldDir;
			this.path = oldPath;
		}
	}

	// Override copyFile to use chunked reading for large files to prevent blocking
	override private function copyFile(src:haxe.io.Input, dst:haxe.io.Output):Void {
		var startTime = Sys.time();
		trace("Starting file copy at " + startTime);

		// Set socket to blocking mode for file transfer
		try {
			request.setBlocking(true);
			trace("Socket set to blocking mode");
		} catch (e:Dynamic) {
			trace("Could not set socket to blocking: " + e);
		}

		// Use writeInput which is typically optimized at the native level
		try {
			var beforeWrite = Sys.time();
			trace("Starting writeInput at " + beforeWrite);

			dst.writeInput(src);

			var afterWrite = Sys.time();
			trace("Finished writeInput at " + afterWrite + " (took " + (afterWrite - beforeWrite) + " seconds)");

			dst.flush();

			var afterFlush = Sys.time();
			trace("Finished flush at " + afterFlush + " (took " + (afterFlush - afterWrite) + " seconds)");
		} catch (e:Dynamic) {
			trace("Error copying file: " + e);
			throw e;
		}

		// Restore socket to non-blocking mode
		try {
			request.setBlocking(false);
			trace("Socket restored to non-blocking mode");
		} catch (e:Dynamic) {
			trace("Could not restore socket to non-blocking: " + e);
		}

		var endTime = Sys.time();
		trace("Finished file copy at " + endTime + " (total time: " + (endTime - startTime) + " seconds)");
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
		sendHeader('Access-Control-Allow-Origin', allowOrigin);
		sendHeader('Access-Control-Allow-Credentials', 'true'); // Remove if not using cookies/auth
		sendHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
		sendHeader('Access-Control-Allow-Headers', 'Content-Type, Accept, Authorization, X-Requested-With');
		sendHeader('Vary', 'Origin');
		if (!cacheEnabled) {
			sendHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
		}
		if (currentSessionId != null) {
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
