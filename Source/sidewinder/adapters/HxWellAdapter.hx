package sidewinder.adapters;

import sidewinder.routing.Router;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.routing.Router.UploadedFile;
import sys.net.Socket;
import sys.net.Host;
import haxe.io.Bytes;
import haxe.Http;
import haxe.ds.StringMap;
import snake.http.HTTPStatus;
import sidewinder.logging.HybridLogger;
import sidewinder.core.WorkerIsland;
import sidewinder.interfaces.IslandManager;
import sidewinder.core.DI;
import sidewinder.interfaces.IWebSocketHandler;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.logging.HybridLogger.LogLevel;
import sidewinder.interfaces.IWebServer;
import sidewinder.interfaces.IWebSocketServer;
import hx.well.websocket.WebSocketSession;
import sidewinder.adapters.HxWellAdapterTypes;

/**
 * Adapter for hxwell server.
 * Connects hxwell's socket handling to SideWinder's auto-router.
 * Refactored to use WorkerIslands via IslandManager for thread-safe processing.
 */
class HxWellAdapter implements IWebServer implements IWebSocketServer {
	var host:String;
	var port:Int;
	var directory:String;
	var numIslands:Int;
	var running:Bool = false;
	var driver:sidewinder.adapters.CustomSocketDriver;
	var islandManager:IslandManager;

	// Inject router to avoid circular dependency with SideWinderRequestHandler
	public var router:Router = Router.instance;

	// WebSocket support
	var websocketHandler:IWebSocketHandler;
	var wsEventQueue:Array<WebSocketEvent> = [];
	var wsMutex = new sys.thread.Mutex();

	public function new(host:String, port:Int, directory:String, islandManager:IslandManager) {
		this.islandManager = islandManager;
		this.host = host;
		this.port = port;
		this.directory = directory;
		this.numIslands = islandManager.getIslandCount();

		// Start a background thread to process WebSocket events if a handler is registered
		// Using sys.thread.Thread.create for HashLink reliability over MainLoop.addThread
		sys.thread.Thread.create(processWebSocketEvents);
	}

	public function start():Void {
		this.running = true;

		var config = new hx.well.http.driver.socket.SocketDriverConfig();
		config.host = host;
		config.port = port;
		config.maxConnections = 512;

		driver = new sidewinder.adapters.CustomSocketDriver(config, this);

		HybridLogger.info('[HxWellAdapter] Starting on $host:$port (Static: $directory)');
		driver.start();
	}

	public function handleRequest():Void {
		// hxwell handles its own requests via driver
	}

	private function processWebSocketEvents():Void {
		while (true) {
			Sys.sleep(0.001); // Don't peg CPU

			if (websocketHandler == null)
				continue;

			var events:Array<WebSocketEvent> = [];
			wsMutex.acquire();
			if (wsEventQueue.length > 0) {
				events = wsEventQueue.copy();
				wsEventQueue = [];
			}
			wsMutex.release();

			for (evt in events) {
				try {
					switch (evt.type) {
						case Open(session):
							websocketHandler.onReady(session);
						case Message(session, text):
							var haxeBytes = haxe.io.Bytes.ofString(text);
							websocketHandler.onData(session, WebSocketOpcode.TEXT, haxeBytes.getData(), haxeBytes.length);
						case Binary(session, data):
							websocketHandler.onData(session, WebSocketOpcode.BINARY, data.getData(), data.length);
						case Close(session):
							websocketHandler.onClose(session);
					}
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] WebSocket event processing error: ' + e);
				}
			}
		}
	}

	public function processQueuedRequest(q:QueuedRequest):Void {
		var scope = DI.createScope();
		DI.setThreadProvider(scope);

		var cleanup = function() {
			DI.resetThreadProvider();
			scope.destroy();
		};

		try {
			// Ensure client socket is in blocking mode for synchronous processing on HashLink.
			// This prevents 'haxe.io.Error.Blocked' during RPC handlers or static file serving
			// if the socket was left in non-blocking mode by a previous operation on the same connection.
			#if sys
			q.socket.setBlocking(true);
			#end
			
			var swRes = createResponse(q.socket);
			var swReq = convertRequest(q.hxRequest, q.socket);

			// Handle session
			var sessionId = swReq.cookies.get("session_id");
			if (sessionId == null) {
				sessionId = Std.string(Math.floor(Math.random() * 1000000000)) + "_" + Std.string(Date.now().getTime());
				swReq.cookies.set("session_id", sessionId);
				swRes.setHeader("Set-Cookie", "session_id=" + sessionId + "; Path=/; HttpOnly");
			}

			// Handle OPTIONS preflight for CORS
			if (swReq.method == "OPTIONS") {
				swRes.sendResponse(HTTPStatus.OK);
				swRes.end();
				cleanup();
				return;
			}

			HybridLogger.info('[HxWellAdapter] ${swReq.method} ${swReq.path}');

			if (router != null) {
				var match = router.find(swReq.method, swReq.path);
				if (match != null) {
					HybridLogger.debug('[HxWellAdapter] Route match found for ${swReq.path}');
					swReq.params = match.params;
					router.handle(swReq, swRes, match.route);
					cleanup();
					return;
				}
			}

			if (directory != null && serveStatic(swReq.path, swRes, q.socket)) {
				HybridLogger.debug('[HxWellAdapter] Static file served for ${swReq.path}');
			} else {
				HybridLogger.warn('[HxWellAdapter] 404 Not Found: ${swReq.path}');
				swRes.sendError(HTTPStatus.NOT_FOUND);
				swRes.end();
			}
			cleanup();
		} catch (e:Dynamic) {
			HybridLogger.error('[HxWellAdapter] Error processing request: ' + e);
			try {
				q.socket.shutdown(false, true);
				q.socket.close();
			} catch (_) {}
			cleanup();
		}
	}

	private function convertRequest(hxReq:hx.well.http.Request, socket:Socket):Request {
		var headers = new Map<String, String>();
		@:privateAccess {
			for (k in hxReq.headers.keys()) {
				headers.set(k, hxReq.headers.get(k));
			}
		}

		var body = hxReq.bodyBytes != null ? hxReq.bodyBytes.toString() : "";

		if (hxReq.requestBytes != null) {
			var firstLine = hxReq.requestBytes.toString().split("\r\n")[0];
			HybridLogger.debug('[HxWellAdapter] Raw Request Line: ' + firstLine);
		}

		HybridLogger.debug('[HxWellAdapter] hxReq fields: ' + Reflect.fields(hxReq).join(", "));
		@:privateAccess {
			HybridLogger.debug('[HxWellAdapter] hxReq.path: ' + hxReq.path);
			HybridLogger.debug('[HxWellAdapter] hxReq.uri: ' + (Reflect.hasField(hxReq, "uri") ? Reflect.field(hxReq, "uri") : "N/A"));
		}

		var jsonBody:Dynamic = null;
		if (headers.get("Content-Type") == "application/json") {
			try {
				jsonBody = haxe.Json.parse(body);
			} catch (e:Dynamic) {}
		}

		var formBody = new Map<String, String>();
		var cookies = new Map<String, String>();
		var cookieHeader = headers.get("Cookie");
		if (cookieHeader != null) {
			var pairs = cookieHeader.split(";");
			for (pair in pairs) {
				var kv = pair.split("=");
				if (kv.length == 2) {
					cookies.set(StringTools.trim(kv[0]), StringTools.trim(kv[1]));
				}
			}
		}

		var files:Array<UploadedFile> = [];

		var rawPath = hxReq.path != null ? hxReq.path : "/";
		if (hxReq.requestBytes != null) {
			var requestLine = hxReq.requestBytes.toString().split("\r\n")[0];
			var lineParts = requestLine.split(" ");
			if (lineParts.length >= 2) {
				rawPath = lineParts[1];
			}
		}

		var path = rawPath.split("?")[0];

		var query = new Map<String, String>();

		// 1. Try to get from hxReq.queries if populated
		if (hxReq.queries != null) {
			for (k in hxReq.queries.keys()) {
				query.set(k, hxReq.queries.get(k));
			}
		}

		// 2. Fallback to raw path if map is still empty
		if (!query.keys().hasNext()) {
			var rawFullPath = "";
			if (hxReq.requestBytes != null) {
				var requestLine = hxReq.requestBytes.toString().split("\r\n")[0];
				var lineParts = requestLine.split(" ");
				if (lineParts.length >= 2) {
					rawFullPath = lineParts[1];
				}
			}

			// If we couldn't get it from raw bytes, use hxReq.path but acknowledge it's already decoded
			if (rawFullPath == "" && hxReq.path != null) {
				// If we don't have raw bytes, we can't reliably get the query from hxReq.path 
				// as hxwell might have already stripped it. But we try one more fallback.
			}
			
			if (rawFullPath != "") {
				var parts = rawFullPath.split("?");
				if (parts.length > 1) {
					var qstr = parts[1];
					for (part in qstr.split("&")) {
						var eqIndex = part.indexOf("=");
						if (eqIndex != -1) {
							var key = part.substring(0, eqIndex);
							var val = part.substring(eqIndex + 1);
							try {
								query.set(StringTools.urlDecode(key), StringTools.urlDecode(val));
							} catch(e:Dynamic) {
								query.set(key, val);
							}
						}
					}
				}
			}
		}

		var finalPath = hxReq.path != null ? hxReq.path : "/";
		finalPath = finalPath.split("?")[0];
		if (!StringTools.startsWith(finalPath, "/")) {
			finalPath = "/" + finalPath;
		}

		var req:Request = {
			method: hxReq.method,
			path: finalPath,
			headers: headers,
			query: query,
			params: new Map<String, String>(),
			body: body,
			jsonBody: jsonBody,
			formBody: formBody,
			cookies: cookies,
			files: files,
			ip: hxReq.ip
		};

		var queryKeyCount = 0;
		for (k in query.keys())
			queryKeyCount++;
		HybridLogger.debug('[HxWellAdapter] Final Query key count: ' + queryKeyCount);

		return req;
	}

	private function createResponse(socket:Socket):Response {
		var statusCode:Int = 200;
		var headers = new Map<String, String>();
		var headersSent = false;
		var response:Response = null;

		response = {
			write: function(s:String) {
				if (!headersSent)
					response.endHeaders();
				try {
					socket.output.writeString(s);
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error in res.write: ' + e);
				}
			},
			setHeader: function(k:String, v:String) {
				headers.set(k, v);
			},
			sendError: function(status:HTTPStatus) {
				statusCode = status.code;
			},
			sendResponse: function(status:HTTPStatus) {
				statusCode = status.code;
			},
			endHeaders: function() {
				if (headersSent)
					return;
				try {
					socket.output.writeString('HTTP/1.1 $statusCode ' + getStatusMessage(statusCode) + '\r\n');
					if (!headers.exists("Content-Type")) {
						headers.set("Content-Type", "text/html; charset=utf-8");
					}

					headers.set("Connection", "close");

					if (!headers.exists("Access-Control-Allow-Origin")) {
						headers.set("Access-Control-Allow-Origin", "*");
					}
					if (!headers.exists("Access-Control-Allow-Methods")) {
						headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
					}
					if (!headers.exists("Access-Control-Allow-Headers")) {
						headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, X-Project-Key, X-API-Key, X-Hub-Signature-256");
					}
					if (!headers.exists("Access-Control-Allow-Credentials")) {
						headers.set("Access-Control-Allow-Credentials", "true");
					}

					for (k in headers.keys()) {
						socket.output.writeString('$k: ${headers.get(k)}\r\n');
					}
					socket.output.writeString('\r\n');
					headersSent = true;
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error writing headers: ' + e);
				}
			},
			end: function() {
				if (!headersSent) {
					response.endHeaders();
				}
				try {
					socket.output.flush();
					socket.shutdown(false, true);
					socket.close();
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error closing socket: ' + e);
					try {
						socket.close();
					} catch (_) {}
				}
			},
			setCookie: function(name:String, value:String, ?options:Dynamic) {
				var cookie = Std.string(name) + "=" + Std.string(value);
				if (options != null) {
					if (Reflect.hasField(options, "path")) {
						var p = Reflect.field(options, "path");
						if (p != null) cookie += "; Path=" + Std.string(p);
					}
					if (Reflect.hasField(options, "domain")) {
						var d = Reflect.field(options, "domain");
						if (d != null) cookie += "; Domain=" + Std.string(d);
					}
					if (Reflect.hasField(options, "maxAge")) {
						var ma = Reflect.field(options, "maxAge");
						if (ma != null) cookie += "; Max-Age=" + Std.string(ma);
					}
					if (Reflect.field(options, "httpOnly") == true)
						cookie += "; HttpOnly";
					if (Reflect.field(options, "secure") == true)
						cookie += "; Secure";
				}
				headers.set("Set-Cookie", cookie);
			}
		};
		return response;
	}

	private function getStatusMessage(code:Int):String {
		return switch (code) {
			case 200: "OK";
			case 201: "Created";
			case 400: "Bad Request";
			case 401: "Unauthorized";
			case 403: "Forbidden";
			case 404: "Not Found";
			case 500: "Internal Server Error";
			default: "Unknown";
		}
	}

	private function serveStatic(path:String, res:Response, socket:Socket):Bool {
		var pathOnly = path.split("?")[0];
		if (pathOnly == "/" || pathOnly == "")
			pathOnly = "/index.html";

		var fileToServe = pathOnly;
		if (StringTools.startsWith(pathOnly, "/static/")) {
			fileToServe = pathOnly.substr("/static".length);
		}

		var baseDir = directory;
		if (!haxe.io.Path.isAbsolute(baseDir)) {
			baseDir = haxe.io.Path.join([Sys.getCwd(), directory]);
		}
		var fullPath = haxe.io.Path.join([baseDir, fileToServe]);

		if (sys.FileSystem.exists(fullPath) && !sys.FileSystem.isDirectory(fullPath)) {
			try {
				var bytes = sys.io.File.getBytes(fullPath);
				var extension = haxe.io.Path.extension(fullPath).toLowerCase();
				var contentType = guessType(extension);

				res.sendResponse(HTTPStatus.OK);
				res.setHeader("Content-Type", contentType);
				res.setHeader("Content-Length", Std.string(bytes.length));
				res.endHeaders();

				try {
					socket.output.writeBytes(bytes, 0, bytes.length);
					socket.output.flush();
					socket.shutdown(false, true);
					socket.close();
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error writing static file bytes: ' + e);
					try {
						socket.close();
					} catch (_) {}
				}
				return true;
			} catch (e:Dynamic) {
				HybridLogger.error('[HxWellAdapter] Error serving static file $fullPath: ' + e);
			}
		}
		return false;
	}

	private function guessType(extension:String):String {
		return switch (extension) {
			case "html", "htm": "text/html";
			case "css": "text/css";
			case "js": "application/javascript";
			case "json": "application/json";
			case "png": "image/png";
			case "jpg", "jpeg": "image/jpeg";
			case "gif": "image/gif";
			case "svg": "image/svg+xml";
			case "txt": "text/plain";
			case "xml": "text/xml";
			default: "application/octet-stream";
		}
	}

	public function stop():Void {
		running = false;
		if (driver != null)
			driver.stop();
	}

	public function getHost():String
		return host;

	public function getPort():Int
		return port;

	public function isRunning():Bool
		return running;

	public function pushRequest(q:QueuedRequest):Void {
		var sessionId:Null<String> = null;
		@:privateAccess {
			var cookieHeader = q.hxRequest.header("Cookie");
			if (cookieHeader != null) {
				var pairs = cookieHeader.split(";");
				for (pair in pairs) {
					var kv = pair.split("=");
					if (kv.length == 2) {
						var key = StringTools.trim(kv[0]);
						if (key == "session_id") {
							sessionId = StringTools.trim(kv[1]);
							break;
						}
					}
				}
			}
		}

		islandManager.dispatch(sessionId, () -> {
			processQueuedRequest(q);
		});
	}

	public function setWebSocketHandler(handler:IWebSocketHandler):Void {
		this.websocketHandler = handler;
		HybridLogger.info('[HxWellAdapter] WebSocket handler registered');
	}

	public function websocketSendText(conn:Dynamic, text:String):Void {
		var session:WebSocketSession = cast conn;
		session.send(text);
	}

	public function websocketSendBinary(conn:Dynamic, data:haxe.io.Bytes):Void {
		var session:WebSocketSession = cast conn;
		session.sendBinary(data);
	}

	public function websocketClose(conn:Dynamic, code:Int = 1000, ?reason:String):Void {
		var session:WebSocketSession = cast conn;
		session.close();
	}

	public function pushWebSocketEvent(evt:WebSocketEvent):Void {
		wsMutex.acquire();
		wsEventQueue.push(evt);
		wsMutex.release();
	}
}
