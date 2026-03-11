package sidewinder;

import hx.well.http.driver.socket.SocketDriver;
import hx.well.http.driver.socket.SocketDriverConfig;
import hx.well.http.driver.socket.SocketRequestParser;
import hx.well.http.Request as HxRequest;
import sys.net.Socket;
import sys.thread.Thread;
import sys.thread.Mutex;
import hx.well.http.RequestStatic;
import hx.well.http.driver.socket.SocketWebSocketHandler;
import hx.well.websocket.WebSocketSession;
import hx.well.websocket.AbstractWebSocketHandler as HxAbstractWebSocketHandler;
import sidewinder.Router;
import sidewinder.IWebSocketHandler;
import snake.http.HTTPStatus;
import haxe.io.Bytes;
import haxe.Exception;

/**
 * Adapter for hxwell web server framework drivers.
 * Bridges hxwell's multi-threaded SocketDriver with SideWinder's single-threaded router loop.
 */
class HxWellAdapter implements IWebServer implements IWebSocketServer {
	private var driver:CustomSocketDriver;
	private var host:String;
	private var port:Int;
	private var running:Bool = false;
	private var islandManager:IslandManager;
	private var directory:String;
	private var websocketHandler:IWebSocketHandler;
	private var wsEventQueue:Array<WebSocketEvent> = [];
	private var wsMutex:Mutex = new Mutex();

	public function new(host:String, port:Int, ?directory:String, numIslands:Int = 4) {
		this.host = host;
		this.port = port;
		this.directory = directory;
		this.islandManager = new IslandManager(numIslands);

		var config = new SocketDriverConfig();
		config.host = host;
		config.port = port;

		this.driver = new CustomSocketDriver(config, this);
	}

	public function start():Void {
		if (!running) {
			running = true;
			Thread.create(() -> {
				try {
					driver.start();
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Driver error: ' + e);
				}
			});
			HybridLogger.info('[HxWellAdapter] Started on $host:$port (background thread)');
		}
	}

	public function handleRequest():Void {
		if (!running)
			return;
		

		// Process WebSocket events
		var wsEvents:Array<WebSocketEvent> = null;
		wsMutex.acquire();
		if (wsEventQueue.length > 0) {
			wsEvents = wsEventQueue.copy();
			wsEventQueue = [];
		}
		wsMutex.release();

		if (wsEvents != null && websocketHandler != null) {
			for (evt in wsEvents) {
				try {
					switch (evt.type) {
						case Open:
							websocketHandler.onConnect();
							websocketHandler.onReady(evt.session);
						case Message:
							websocketHandler.onData(evt.session, IWebSocketHandler.WebSocketOpcode.TEXT, @:privateAccess evt.data.b, evt.data.length);
						case Binary:
							websocketHandler.onData(evt.session, IWebSocketHandler.WebSocketOpcode.BINARY, @:privateAccess evt.data.b, evt.data.length);
						case Close:
							websocketHandler.onClose(evt.session);
					}
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] WebSocket event error: ' + e);
				}
			}
		}
	}

	private function processQueuedRequest(q:QueuedRequest):Void {
		try {
			var swRes = createResponse(q.socket);
			var swReq = convertRequest(q.hxRequest, q.socket);

			// Handle OPTIONS preflight for CORS
			if (swReq.method == "OPTIONS") {
				swRes.sendResponse(HTTPStatus.OK);
				swRes.end();
				return;
			}

			var match = SideWinderRequestHandler.router.find(swReq.method, swReq.path);
			if (match != null) {
				swReq.params = match.params;
				SideWinderRequestHandler.router.handle(swReq, swRes, match.route);
			} else if (directory != null && serveStatic(swReq.path, swRes, q.socket)) {
				// Static file served
			} else {
				swRes.sendError(HTTPStatus.NOT_FOUND);
				swRes.end();
			}
		} catch (e:Dynamic) {
			HybridLogger.error('[HxWellAdapter] Error processing request: ' + e);
			try {
				q.socket.close();
			} catch (_) {}
		}
	}

	private function convertRequest(hxReq:HxRequest, socket:Socket):Router.Request {
		var headers = new Map<String, String>();
		@:privateAccess {
			for (k in hxReq.headers.keys()) {
				headers.set(k, hxReq.headers.get(k));
			}
		}

		var body = hxReq.bodyBytes != null ? hxReq.bodyBytes.toString() : "";
		var contentType = headers.get("Content-Type");
		if (contentType == null)
			contentType = headers.get("content-type");

		var jsonBody:Dynamic = null;
		var formBody = new haxe.ds.StringMap<String>();
		var files:Array<UploadedFile> = [];

		// Parse body based on content-type
		if (contentType != null) {
			if (contentType.indexOf("application/json") != -1) {
				try {
					jsonBody = haxe.Json.parse(body);
				} catch (e:Dynamic) {
					HybridLogger.warn('[HxWellAdapter] Failed to parse JSON: $e');
				}
			} else if (contentType.indexOf("application/x-www-form-urlencoded") != -1) {
				for (pair in body.split("&")) {
					var kv = pair.split("=");
					if (kv.length == 2) {
						formBody.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
					}
				}
			} else if (contentType.indexOf("multipart/form-data") != -1) {
				var multipartData = MultipartParser.parseMultipart(body, contentType);
				files = multipartData.files;
				formBody = multipartData.fields;
			}
		}

		// Parse cookies
		var cookies = new haxe.ds.StringMap<String>();
		@:privateAccess {
			for (k in hxReq.cookies.keys()) {
				cookies.set(k, hxReq.cookies.get(k));
			}
		}

		// Handle session
		var sessionId = cookies.get("session_id");
		if (sessionId == null) {
			sessionId = Std.string(Math.floor(Math.random() * 1000000000)) + "_" + Std.string(Date.now().getTime());
			cookies.set("session_id", sessionId);
		}

		// SideWinder Request structure
		var req:Router.Request = {
			method: hxReq.method,
			path: hxReq.path,
			headers: headers,
			query: hxReq.queries,
			params: new Map<String, String>(),
			body: body,
			jsonBody: jsonBody,
			formBody: formBody,
			cookies: cookies,
			files: files,
			ip: hxReq.ip
		};

		return req;
	}

	private function createResponse(socket:Socket):Router.Response {
		var statusCode:Int = 200;
		var headers = new Map<String, String>();
		var headersSent = false;
		var res:Router.Response = null;

		res = {
			write: function(s:String) {
				if (!headersSent)
					res.endHeaders();
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

					// Always set CORS headers
					if (!headers.exists("Access-Control-Allow-Origin")) {
						headers.set("Access-Control-Allow-Origin", "*");
					}
					if (!headers.exists("Access-Control-Allow-Methods")) {
						headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
					}
					if (!headers.exists("Access-Control-Allow-Headers")) {
						headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");
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
					res.endHeaders();
				}
				try {
					socket.output.flush();
					socket.close();
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error closing socket: ' + e);
				}
			},
			setCookie: function(name, value, ?options) {
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
				headers.set("Set-Cookie", cookie);
			}
		};
		return res;
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

	private function serveStatic(path:String, res:Router.Response, socket:Socket):Bool {
		var pathOnly = path.split("?")[0];
		if (pathOnly == "/" || pathOnly == "")
			pathOnly = "/index.html";

		var fileToServe = pathOnly;
		if (StringTools.startsWith(pathOnly, "/static/")) {
			fileToServe = pathOnly.substr("/static".length);
		}

		var fullPath = haxe.io.Path.join([Sys.getCwd(), directory, fileToServe]);

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
					socket.output.writeString(bytes.toString());
					socket.output.flush();
					socket.close();
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error writing static file bytes: ' + e);
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
		driver.stop();
	}

	public function getHost():String
		return host;

	public function getPort():Int
		return port;

	public function isRunning():Bool
		return running;

	public function enqueue(q:QueuedRequest):Void {
		// Extract session ID for sticky routing
		var sessionId:Null<String> = null;
		@:privateAccess {
			var cookieHeader = q.hxRequest.header("Cookie");
			if (cookieHeader != null) {
				var pairs = cookieHeader.split(";");
				for (pair in pairs) {
					var kv = pair.split("=");
					if (kv.length == 2 && StringTools.trim(kv[0]) == "session_id") {
						sessionId = StringTools.trim(kv[1]);
						break;
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
		session.close(); // hxwell session close handles the handshake
	}

	private function enqueueWsEvent(evt:WebSocketEvent):Void {
		wsMutex.acquire();
		wsEventQueue.push(evt);
		wsMutex.release();
	}
}

private enum WebSocketEventType {
	Open;
	Message;
	Binary;
	Close;
}

private typedef WebSocketEvent = {
	var type:WebSocketEventType;
	var session:WebSocketSession;
	@:optional var data:Bytes;
}

private class HxWellWebSocketBridge extends HxAbstractWebSocketHandler {
	private var adapter:HxWellAdapter;

	public function new(adapter:HxWellAdapter) {
		super();
		this.adapter = adapter;
	}

	public function onOpen(session:WebSocketSession):Void {
		@:privateAccess adapter.enqueueWsEvent({type: Open, session: session});
	}

	public function onMessage(session:WebSocketSession, message:String):Void {
		@:privateAccess adapter.enqueueWsEvent({type: Message, session: session, data: Bytes.ofString(message)});
	}

	public function onBinary(session:WebSocketSession, data:Bytes):Void {
		@:privateAccess adapter.enqueueWsEvent({type: Binary, session: session, data: data});
	}

	public function onClose(session:WebSocketSession, code:Int, reason:String):Void {
		@:privateAccess adapter.enqueueWsEvent({type: Close, session: session});
	}

	public function onError(session:WebSocketSession, error:Exception):Void {
		HybridLogger.error('[HxWellAdapter] WebSocket error for session ${session.id}: ' + error);
	}
}

private typedef QueuedRequest = {
	var hxRequest:HxRequest;
	var socket:Socket;
}

@:access(hx.well.http.driver.socket.SocketDriver)
private class CustomSocketDriver extends SocketDriver {
	private var adapter:HxWellAdapter;

	public function new(config, adapter) {
		super(config);
		this.adapter = adapter;
	}

	override public function process(socket:Socket):Void {
		// Run in background threadpool provided by SocketDriver
		@:privateAccess executor.submit(() -> {
			try {
				socket.setTimeout(30);
				var hxReq = hx.well.http.driver.socket.SocketRequestParser.parseFromSocket(socket);

				// Check for WebSocket upgrade
				var upgrade = hxReq.header("Upgrade");
				if (upgrade != null && upgrade.toLowerCase() == "websocket") {
					var bridge = new HxWellWebSocketBridge(adapter);
					// This blocks the background thread and handles the message loop
					hx.well.http.driver.socket.SocketWebSocketHandler.upgrade(socket, hxReq, bridge);
					return;
				}
				
				// Handle body parsing if Content-Length is present
				var contentLen = hxReq.header("Content-Length");
				
				if (contentLen != null) {
					var len = Std.parseInt(contentLen);
					if (len > 0) {
						var input = new hx.well.http.driver.socket.SocketInput(socket);
						input.length = len;
						
						// Set static context so hxwell internal parsers can find the request
						hx.well.http.RequestStatic.set(hxReq);
						try {
							hx.well.http.driver.socket.SocketRequestParser.parseBody(hxReq, input);
						} catch (e:Dynamic) {
							// If abort() was called or other parse error, we log it
							HybridLogger.warn('[HxWellAdapter] Body parse error: ' + e);
						}
						hx.well.http.RequestStatic.set(null);
					}
				}
				
				adapter.enqueue({hxRequest: hxReq, socket: socket});
			} catch (e:Dynamic) {
				HybridLogger.error('[HxWellAdapter] Background parse error: ' + e);
				try {
					socket.close();
				} catch (_) {}
			}
		});
	}
}
