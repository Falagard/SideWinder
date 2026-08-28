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
import sidewinder.interfaces.IWebSocketHandler;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.logging.HybridLogger.LogLevel;
import sidewinder.interfaces.IWebServer;
import sidewinder.interfaces.IWebSocketServer;
import hx.well.websocket.WebSocketSession;
import sidewinder.adapters.HxWellAdapterTypes;
import sidewinder.http.IHttpServerOptions;
import sidewinder.http.HttpServerOptions;
import sidewinder.http.IRequestIdFactory;
import sidewinder.http.SequentialRequestIdFactory;
import sidewinder.http.IRequestScope;
import sidewinder.http.IRequestScopeFactory;
import sidewinder.http.MapRequestScopeFactory;
import sidewinder.http.WebSocketAdmissionPolicy;

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

	// SIDEWINDER-CORE-DECOUPLING-S1 (Tasks C/D/E/F/G).
	//
	// These three collaborators replace what used to be
	// `#if haxestack_platform_server` branches naming
	// `core.IServerConfig`, `app.util.RequestId` and `app.services.ProjectContext`.
	// The adapter is now configured by composition and has no compile-time
	// knowledge of any host application.
	//
	// Defaults are container-free, so a lightweight hxcpp application can host
	// routes with neither hx-injection nor a UUID library linked in.
	var options:IHttpServerOptions;
	var requestIdFactory:IRequestIdFactory;
	var requestScopeFactory:IRequestScopeFactory;

	// Task K: hard ceiling on concurrent WebSocket connections.
	var wsAdmission:WebSocketAdmissionPolicy;

	// Hook invoked after a request is converted, so a host application can set up
	// per-request scoped services (e.g. tenant context). Present in both platform
	// and standalone (generated app) builds — must NOT be wrapped in #if.
	public static var onScopeSetup:Null<(scope:Dynamic, request:Dynamic)->Void> = null;

	// SIDEWINDER-CORE-DECOUPLING-S1 (Task E): typed form of the hook above.
	// Receives the framework's `IRequestScope`, which carries the request id and
	// (for container-backed scopes) `unwrap()`s to the container scope. Prefer
	// this in new code; `onScopeSetup` is retained unchanged for existing
	// callers such as StackServerSDK.
	//
	// Both hooks fire, `onRequestScope` first, once per request, immediately
	// after the request is converted and before any route handler runs.
	public static var onRequestScope:Null<(scope:IRequestScope, request:Dynamic)->Void> = null;

	// Inject router to avoid circular dependency with SideWinderRequestHandler
	public var router:Router = Router.instance;

	// Hook called when an unhandled exception escapes a request handler (500 errors).
	// Receives: method, path, request headers, exception, stack trace.
	public static var onRequestError:Null<(method:String, path:String, headers:Map<String,String>, e:Dynamic, stack:String)->Void>;

	// Optional hook to classify thrown exceptions and override the HTTP response status.
	// Return a non-null HTTPStatus to use instead of 500. Called before writing the response.
	public static var onClassifyRequestError:Null<(e:Dynamic)->Null<snake.http.HTTPStatus>> = null;

	// Invoked once, synchronously, from inside start() — after the listening socket is
	// bound and set to listen, before the blocking accept loop begins. This is the
	// correct readiness signal: start() itself never returns for this driver (it runs
	// an unconditional accept loop), so a caller waiting on start() to return for
	// readiness will wait forever. SERVER-HEADLESS-BOOT-S1 (D-8).
	public var onStarted:Null<Void->Void> = null;

	// WebSocket support
	var websocketHandler:IWebSocketHandler;
	var wsEventQueue:Array<WebSocketEvent> = [];
	var wsMutex = new sys.thread.Mutex();
	// SIDEWINDER-CORE-DECOUPLING-S1 (Task L): the WebSocket event pump used to
	// spin at 1ms. Park on a counting semaphore instead; `pushWebSocketEvent`
	// releases it.
	var wsSignal = new sys.thread.Lock();

	/**
	 * @param options            Transport limits and worker sizing. Defaults to
	 *                           `HttpServerOptions(host, port)`, whose defaults are
	 *                           validated to be non-exhaustible (Task K).
	 * @param requestIdFactory   Defaults to `SequentialRequestIdFactory` (no UUID
	 *                           dependency). The Server supplies one wrapping its
	 *                           own `app.util.RequestId`.
	 * @param requestScopeFactory Defaults to `MapRequestScopeFactory` -- NO DI
	 *                           container. Applications that use hx-injection pass
	 *                           `sidewinder.integration.injection.DiRequestScopeFactory`.
	 */
	public function new(host:String, port:Int, directory:String, islandManager:IslandManager, ?options:IHttpServerOptions,
			?requestIdFactory:IRequestIdFactory, ?requestScopeFactory:IRequestScopeFactory) {
		this.islandManager = islandManager;
		this.host = host;
		this.port = port;
		this.directory = directory;
		this.numIslands = islandManager.getIslandCount();

		this.options = options != null ? options : new HttpServerOptions(host, port);
		this.requestIdFactory = requestIdFactory != null ? requestIdFactory : new SequentialRequestIdFactory();
		this.requestScopeFactory = requestScopeFactory != null ? requestScopeFactory : new MapRequestScopeFactory();
		this.wsAdmission = new WebSocketAdmissionPolicy(this.options.maxWebSocketConnections);

		// Synchronize message size limit with the driver
		hx.well.http.driver.socket.SocketWebSocketHandler.maxMessageSize = this.options.maxWebSocketMessageSize;

		// Using sys.thread.Thread.create for HashLink reliability over MainLoop.addThread
		sys.thread.Thread.create(processWebSocketEvents);
	}

	public function start():Void {
		this.running = true;

		var config = new hx.well.http.driver.socket.SocketDriverConfig();
		config.host = host;
		config.port = port;
		config.maxConnections = options.maxConnections;
		// Task K: HxWell's own default is 10, which deadlocks at 10 concurrent
		// WebSocket clients. `HttpServerOptions` validated this value against
		// maxWebSocketConnections + httpWorkerHeadroom at construction.
		config.poolSize = options.workerPoolSize;
		config.onStart = () -> {
			// FOOTNOTE-MEDIA-WORKER-S1 Task 11 (Failure B fix): mark every
			// currently-open file descriptor (including the listening socket
			// that was just bound+listen()'d inside SocketDriver.start(),
			// strictly before this callback fires) close-on-exec, so no
			// spawned child process (sys.io.Process — worker executables,
			// ffmpeg/ffprobe, installers, command runners, etc.) inherits
			// this server's listening socket. Without this, an orphaned
			// descendant of a killed child can keep the port bound after a
			// hard restart, causing the restarted server's own bind() to
			// fail. See sidewinder.native.FdUtilNative and the consuming
			// project's native/fdutil/fdutil_hl.c for the full writeup.
			// This runs for every server built on HxWellAdapter, not just
			// FootNote's companion mode.
			#if (hl && !macro)
			try {
				var marked = sidewinder.native.FdUtilNative.setCloexecOnOpenFds(3);
				if (marked == sidewinder.native.FdUtilNative.NOT_APPLIED) {
					HybridLogger.info('[HxWellAdapter] FD_CLOEXEC sweep skipped: this build was not compiled with -D sidewinder_fdutil (no matching fdutil.hdll for this platform) -- spawned child processes may inherit the listening socket.');
				} else {
					HybridLogger.info('[HxWellAdapter] FD_CLOEXEC swept on $marked open file descriptor(s) after listener bind (fd 3+).');
				}
			} catch (e:Dynamic) {
				HybridLogger.warn('[HxWellAdapter] FD_CLOEXEC sweep failed (fdutil.hdll missing or unsupported platform?): $e');
			}
			#end
			if (onStarted != null) onStarted();
		};

		driver = new sidewinder.adapters.CustomSocketDriver(config, this, options, wsAdmission);

		HybridLogger.info('[HxWellAdapter] Starting on $host:$port (Static: $directory)');
		driver.start();
	}

	public function handleRequest():Void {
		// hxwell handles its own requests via driver
	}

	private function processWebSocketEvents():Void {
		while (true) {
			// Blocks until an event is queued, or 1s elapses. The timeout keeps
			// the loop responsive to a websocketHandler being installed after
			// the pump thread started.
			wsSignal.wait(1.0);

			if (websocketHandler == null)
				continue;

			#if hl hl.Gc.enable(false); #end
			var events:Array<WebSocketEvent> = [];
			wsMutex.acquire();
			if (wsEventQueue.length > 0) {
				events = wsEventQueue.copy();
				wsEventQueue = [];
			}
			wsMutex.release();
			#if hl hl.Gc.enable(true); #end

			for (evt in events) {
				try {
					switch (evt.type) {
						case Connect(session, swReq):
							if (!websocketHandler.onConnect(swReq)) {
								HybridLogger.warn('[HxWellAdapter] WebSocket connection rejected by handler for session ${session.id}');
								session.close();
							}
						case Open(session):
							websocketHandler.onReady(session);
						case Message(session, text):
							// SIDEWINDER-CORE-DECOUPLING-S1: `IWebSocketHandler.onData`
							// declares `hl.Bytes` on HashLink but `haxe.io.Bytes`
							// everywhere else. Passing `getData()` unconditionally
							// compiled only on HL and was a hard type error on hxcpp
							// (`haxe.io.BytesData should be haxe.io.Bytes`) -- proof
							// this branch had never been built for cpp.
							var haxeBytes = haxe.io.Bytes.ofString(text);
							websocketHandler.onData(session, WebSocketOpcode.TEXT, #if hl haxeBytes.getData() #else haxeBytes #end, haxeBytes.length);
						case Binary(session, data):
							websocketHandler.onData(session, WebSocketOpcode.BINARY, #if hl data.getData() #else data #end, data.length);
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
		var requestId = requestIdFactory.generate();

		// The scope is whatever the host application's factory produced. For a
		// DI application this installs the hx-injection thread provider exactly
		// as the inline code used to; for a lightweight application it is a
		// plain attribute bag and no container exists.
		var scope:IRequestScope = requestScopeFactory.create(requestId);

		var maxHeaderSize = options.maxHeaderSize;
		var maxUrlLength = options.maxUrlLength;
		var maxRequestBodySize = options.maxRequestBodySize;

		var swRes = createResponse(q.socket, requestId);

		var cleanup = function() {
			// `dispose()` is idempotent; for the DI-backed scope it resets the
			// thread provider and destroys the container scope, which is what
			// this used to do inline.
			scope.dispose();
		};

		// Capture request context for crash reporting — populated after convertRequest succeeds.
		var _crashMethod  = q.hxRequest.method;
		var _crashPath    = q.hxRequest.path;
		var _crashHeaders = new Map<String, String>();
		try {
			// Ensure client socket is in blocking mode for synchronous processing on HashLink.
			// This prevents 'haxe.io.Error.Blocked' during RPC handlers or static file serving
			// if the socket was left in non-blocking mode by a previous operation on the same connection.
			#if sys
			q.socket.setBlocking(true);
			#end

			var swReq = convertRequest(q.hxRequest, q.socket);
			_crashMethod  = swReq.method;
			_crashPath    = swReq.path;
			_crashHeaders = swReq.headers;

			// Per-request scope setup hook (both platform and standalone builds).
			// Hand the host application the container-specific scope object when
			// there is one (preserving the existing `scope.getService(...)`
			// contract used by StackServerSDK), otherwise the scope itself.
			if (onRequestScope != null) onRequestScope(scope, swReq);
			if (onScopeSetup != null) {
				var raw = scope.unwrap();
				onScopeSetup(raw != null ? raw : cast scope, swReq);
			}

			// Enforce Header Size Limit
			var totalHeaderSize = 0;
			for (k in swReq.headers.keys()) {
				totalHeaderSize += k.length + swReq.headers.get(k).length + 4; // Approximation
			}
			if (totalHeaderSize > maxHeaderSize) {
				HybridLogger.warn('[HxWellAdapter] [$requestId] Headers too large: $totalHeaderSize > ${maxHeaderSize}');
				swRes.sendError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE);
				swRes.end();
				cleanup();
				return;
			}

			// Enforce URL length limit
			if (swReq.path.length > maxUrlLength) {
				HybridLogger.warn('[HxWellAdapter] [$requestId] URL too long: ${swReq.path.length} > ${maxUrlLength}');
				swRes.sendError(HTTPStatus.REQUEST_URI_TOO_LONG);
				swRes.end();
				cleanup();
				return;
			}

			// Enforce request body size limit
			if (swReq.rawBodyBytes != null && swReq.rawBodyBytes.length > maxRequestBodySize) {
				HybridLogger.warn('[HxWellAdapter] [$requestId] Body too large: ${swReq.rawBodyBytes.length} > ${maxRequestBodySize}');
				swRes.sendError(HTTPStatus.REQUEST_ENTITY_TOO_LARGE);
				swRes.end();
				cleanup();
				return;
			}

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

			HybridLogger.info('[HxWellAdapter] [$requestId] ${swReq.method} ${swReq.path}');
            var headerSummary = [for (k in swReq.headers.keys()) '$k: ${swReq.headers.get(k)}'].join(", ");
            HybridLogger.debug('[HxWellAdapter] [$requestId] Request Headers: $headerSummary');

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
			HybridLogger.error('[HxWellAdapter] [$requestId] Error processing request: ' + e);
			var eStack = "";
			#if hl
			eStack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			HybridLogger.error(eStack);
			#end
			if (onRequestError != null) {
				try {
					onRequestError(_crashMethod, _crashPath, _crashHeaders, e, eStack);
				} catch (_:Dynamic) {}
			}
			try {
				if (!@:privateAccess (swRes:Dynamic).headersSent) {
					var errorStatus = HTTPStatus.INTERNAL_SERVER_ERROR;
					if (onClassifyRequestError != null) {
						var classified = onClassifyRequestError(e);
						if (classified != null) errorStatus = classified;
					}
					swRes.sendResponse(errorStatus);
					swRes.write(haxe.Json.stringify({
						success: false,
						error: "Request failed",
						requestId: requestId
					}));
					swRes.end();
				} else {
					q.socket.shutdown(false, true);
					q.socket.close();
				}
			} catch (_) {
				try {
					q.socket.close();
				} catch (__) {}
			}
			cleanup();
		}
	}

	private function convertRequest(hxReq:hx.well.http.Request, socket:Socket):Request {
		var headers = new Map<String, String>();
		@:privateAccess {
            var keys = [];
			for (k in hxReq.headers.keys()) {
				headers.set(k, hxReq.headers.get(k));
                keys.push(k);
			}
            HybridLogger.info('[HxWellAdapter] Incoming Header Keys: ' + keys.join(", "));
		}

		var body = hxReq.bodyBytes != null ? hxReq.bodyBytes.toString() : "";

		if (hxReq.requestBytes != null) {
			var raw = hxReq.requestBytes.toString();
			var firstLine = raw.split("\r\n")[0];
			HybridLogger.debug('[HxWellAdapter] Raw Request Line: ' + firstLine);
			HybridLogger.debug('[HxWellAdapter] Full Raw Headers:\n' + raw.split("\r\n\r\n")[0]);
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
			rawBodyBytes: hxReq.bodyBytes,
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

	private function createResponse(socket:Socket, requestId:String):Response {
		var statusCode:Int = 200;
		var headers = new Map<String, String>();
		var headersSent = false;
		var response:Response = null;

		headers.set("X-Request-ID", requestId);

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
			writeBytes: function(b:haxe.io.Bytes) {
				if (!headersSent)
					response.endHeaders();
				try {
					socket.output.writeBytes(b, 0, b.length);
				} catch (e:Dynamic) {
					HybridLogger.error('[HxWellAdapter] Error in res.writeBytes: ' + e);
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
					HybridLogger.info('[HxWellAdapter] Response: $statusCode ' + getStatusMessage(statusCode));
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
		// Wake the event pump (Task L: replaces its 1ms poll).
		wsSignal.release();
	}
}
