package sidewinder;

import sidewinder.native.CivetWebNative;
import sidewinder.native.CivetWebNative.CivetWebRequest;
import sidewinder.native.CivetWebNative.CivetWebResponse;
import sidewinder.Router;
import sidewinder.IWebSocketHandler;
import haxe.io.Bytes;

/**
 * CivetWeb HTTP server adapter using HashLink native bindings.
 * Processes requests synchronously in the CivetWeb callback thread.
 * 
 * Features:
 * - JSON and form body parsing
 * - Cookie parsing and session management
 * - CORS/OPTIONS support
 * - Multipart file upload support
 * - WebSocket support
 * 
 * Requires: civetweb.hdll in Export/hl/bin/
 * To build: cd native/civetweb && make && make install
 */
class CivetWebAdapter implements IWebServer {
	private var host:String;
	private var port:Int;
	private var running:Bool;
	private var serverHandle:CivetWebNative;
	private var documentRoot:String;
	private var requestHandler:Router.Request->Router.Response;
	private var websocketHandler:IWebSocketHandler;
	private var corsEnabled:Bool = true;
	private var sessionStore:Map<String, Float> = new Map();
	
	/**
	 * Create a new CivetWeb adapter.
	 * @param host Server host address (e.g., "127.0.0.1")
	 * @param port Server port number (e.g., 8000)
	 * @param documentRoot Optional document root for serving static files
	 */
	public function new(host:String, port:Int, ?documentRoot:String, ?handler:Router.Request->Router.Response) {
		this.host = host;
		this.port = port;
		this.running = false;
		this.serverHandle = null;
		this.documentRoot = documentRoot != null ? documentRoot : "./static";
		this.requestHandler = handler;
		
		HybridLogger.info('[CivetWebAdapter] Initialized for $host:$port');
		HybridLogger.info('[CivetWebAdapter] Document root: ${this.documentRoot}');
		
		// Create native server instance
		var hostBytes = @:privateAccess host.toUtf8();
		var docRootBytes = @:privateAccess this.documentRoot.toUtf8();
		
		try {
			serverHandle = CivetWebNative.create(hostBytes, port, docRootBytes);
			HybridLogger.info('[CivetWebAdapter] Native CivetWeb server created');
		} catch (e:Dynamic) {
			HybridLogger.error('[CivetWebAdapter] Failed to create server: $e');
			throw e;
		}
	}

	public function start():Void {
		if (!running && serverHandle != null) {
			// Process requests synchronously in callback
			var callback = function(req:Dynamic):CivetWebResponse {
				return handleNativeRequest(req);
			};
			
			try {
				var started = CivetWebNative.start(serverHandle, callback);
				if (started) {
					running = true;
					HybridLogger.info('[CivetWebAdapter] Server started on $host:$port');
					HybridLogger.info('[CivetWebAdapter] Access at http://$host:$port');
				} else {
					HybridLogger.error('[CivetWebAdapter] Failed to start server');
				}
			} catch (e:Dynamic) {
				HybridLogger.error('[CivetWebAdapter] Error starting server: $e');
				throw e;
			}
		}
	}
	
	/**
	 * No-op for CivetWeb (processes synchronously in callback)
	 */
	public function handleRequest():Void {
		// CivetWeb processes requests synchronously in the native callback
		// This method is kept for IWebServer interface compatibility
	}
	
	/**
	 * Handle incoming HTTP requests from CivetWeb (called from C thread)
	 */
	private function handleNativeRequest(reqData:Dynamic):CivetWebResponse {
		try {
			var req:CivetWebRequest = cast reqData;
			var headers = parseHeaders(req.headers);
			var pathOnly = req.uri.split("?")[0];
			
			// Handle OPTIONS preflight for CORS
			if (corsEnabled && req.method == "OPTIONS") {
				return {
					statusCode: 200,
					contentType: "text/plain",
					body: "",
					bodyLength: 0
				};
			}
			
			// Parse body based on content-type
			var contentType = headers.get("Content-Type");
			if (contentType == null) contentType = headers.get("content-type");
			
			var jsonBody:Dynamic = null;
			var formBody = new haxe.ds.StringMap<String>();
			var files:Array<UploadedFile> = [];
			
			// Parse JSON
			if (contentType != null && contentType.indexOf("application/json") != -1) {
				try {
					jsonBody = haxe.Json.parse(req.body);
				} catch (e:Dynamic) {
					HybridLogger.warn('[CivetWebAdapter] Failed to parse JSON: $e');
				}
			}
			// Parse URL-encoded form
			else if (contentType != null && contentType.indexOf("application/x-www-form-urlencoded") != -1) {
				for (pair in req.body.split("&")) {
					var kv = pair.split("=");
					if (kv.length == 2) {
						formBody.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
					}
				}
			}
			// Parse multipart (file uploads)
			else if (contentType != null && contentType.indexOf("multipart/form-data") != -1) {
				var multipartData = MultipartParser.parseMultipart(req.body, contentType);
				files = multipartData.files;
				formBody = multipartData.fields;
			}
			
			// Parse cookies
			var cookies = parseCookies(headers.get("Cookie"));
			
			// Handle session
			var sessionId = cookies.get("session_id");
			var newSession = false;
			if (sessionId == null) {
				sessionId = generateSessionId();
				cookies.set("session_id", sessionId);
				newSession = true;
			}
			sessionStore.set(sessionId, Date.now().getTime());
			
			// Build router request
			var routerReq:Router.Request = {
				method: req.method,
				path: pathOnly,
				query: parseQueryString(req.queryString),
				headers: headers,
				body: req.body,
				jsonBody: jsonBody,
				formBody: formBody,
				params: new Map<String, String>(),
				cookies: cookies,
				files: files,
				ip: req.remoteAddr
			};
			
			// Call the request handler if set, otherwise return 404
			var response:Router.Response;
			if (requestHandler != null) {
				response = requestHandler(routerReq);
				HybridLogger.debug('[CivetWebAdapter] ${req.method} ${pathOnly} -> ${response.statusCode}');
			} else {
				response = {
					statusCode: 404,
					body: "Not Found",
					headers: new Map<String, String>()
				};
			}
			
			// Add CORS headers if enabled
			if (corsEnabled) {
				if (!response.headers.exists("Access-Control-Allow-Origin")) {
					response.headers.set("Access-Control-Allow-Origin", "*");
				}
				if (!response.headers.exists("Access-Control-Allow-Methods")) {
					response.headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
				}
				if (!response.headers.exists("Access-Control-Allow-Headers")) {
					response.headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
				}
			}
			
			// Add session cookie if new
			if (newSession) {
				response.headers.set("Set-Cookie", 'session_id=$sessionId; Path=/; HttpOnly');
			}
			
			// Convert Router.Response to CivetWebResponse
			var respContentType = response.headers.get("Content-Type");
			if (respContentType == null) respContentType = "text/html; charset=utf-8";
			
			return {
				statusCode: response.statusCode,
				contentType: respContentType,
				body: response.body != null ? response.body : "",
				bodyLength: response.body != null ? response.body.length : 0
			};
		} catch (e:Dynamic) {
			HybridLogger.error('[CivetWebAdapter] Error handling request: $e');
			return {
				statusCode: 500,
				contentType: "text/plain",
				body: "Internal Server Error",
				bodyLength: 21
			};
		}
	}
	
	/**
	 * Parse headers from CivetWeb headers string format
	 * Format: "Name: Value\nName: Value\n"
	 */
	private function parseHeaders(headersStr:String):Map<String, String> {
		var result = new Map<String, String>();
		if (headersStr == null || headersStr == "") return result;
		
		var lines = headersStr.split("\n");
		for (line in lines) {
			if (line == "") continue;
			var colonPos = line.indexOf(":");
			if (colonPos > 0) {
				var name = line.substr(0, colonPos);
				var value = StringTools.trim(line.substr(colonPos + 1));
				result.set(name, value);
			}
		}
		return result;
	}

	/**
	 * Parse query string into map
	 */
	private function parseQueryString(qs:String):Map<String, String> {
		var result = new Map<String, String>();
		if (qs == null || qs == "") return result;
		
		var pairs = qs.split("&");
		for (pair in pairs) {
			var kv = pair.split("=");
			if (kv.length >= 2) {
				result.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
			} else if (kv.length == 1) {
				result.set(StringTools.urlDecode(kv[0]), "");
			}
		}
		return result;
	}
	
	/**
	 * Parse cookies from Cookie header
	 */
	private function parseCookies(cookieHeader:String):haxe.ds.StringMap<String> {
		var cookies = new haxe.ds.StringMap<String>();
		if (cookieHeader == null || cookieHeader == "") return cookies;
		
		for (pair in cookieHeader.split(";")) {
			var kv = pair.split("=");
			if (kv.length == 2) {
				cookies.set(StringTools.trim(kv[0]), StringTools.trim(kv[1]));
			}
		}
		return cookies;
	}
	
	/**
	 * Generate a unique session ID
	 */
	private function generateSessionId():String {
		return Std.string(Math.floor(Math.random() * 1000000000)) + "_" + Std.string(Date.now().getTime());
	}

	public function stop():Void {
		if (running && serverHandle != null) {
			try {
				CivetWebNative.stop(serverHandle);
				running = false;
				HybridLogger.info('[CivetWebAdapter] Server stopped');
			} catch (e:Dynamic) {
				HybridLogger.error('[CivetWebAdapter] Error stopping server: $e');
			}
		}
	}

	public function getHost():String {
		return host;
	}

	public function getPort():Int {
		return port;
	}

	public function isRunning():Bool {
		return running;
	}
	
	/**
	 * Set WebSocket handler for managing WebSocket connections
	 * @param handler WebSocket handler implementation
	 */
	public function setWebSocketHandler(handler:IWebSocketHandler):Void {
		this.websocketHandler = handler;
		
		// Register WebSocket callbacks with native layer
		CivetWebNative.setWebSocketConnectHandler(function(result:Int):Void {
			if (websocketHandler != null) {
				var accepted = websocketHandler.onConnect();
				// Store result for C layer (1 = accept, 0 = reject)
				// Note: This is simplified, real implementation would need proper return value handling
			}
		});
		
		CivetWebNative.setWebSocketReadyHandler(function(conn:Dynamic):Void {
			if (websocketHandler != null) {
				websocketHandler.onReady(conn);
			}
		});
		
		CivetWebNative.setWebSocketDataHandler(function(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
			if (websocketHandler != null) {
				websocketHandler.onData(conn, flags, data, length);
			}
		});
		
		CivetWebNative.setWebSocketCloseHandler(function(conn:Dynamic):Void {
			if (websocketHandler != null) {
				websocketHandler.onClose(conn);
			}
		});
		
		HybridLogger.info('[CivetWebAdapter] WebSocket handler registered');
	}
	
	/**
	 * Send data through a WebSocket connection
	 * @param conn Connection handle
	 * @param text Text data to send
	 * @return Bytes sent or -1 on error
	 */
	public function websocketSendText(conn:Dynamic, text:String):Int {
		var bytes = @:privateAccess text.toUtf8();
		return CivetWebNative.websocketSend(conn, WebSocketOpcode.TEXT, bytes, text.length);
	}
	
	/**
	 * Send binary data through a WebSocket connection
	 * @param conn Connection handle
	 * @param data Binary data to send
	 * @return Bytes sent or -1 on error
	 */
	public function websocketSendBinary(conn:Dynamic, data:haxe.io.Bytes):Int {
		var hlBytes = @:privateAccess data.b;
		return CivetWebNative.websocketSend(conn, WebSocketOpcode.BINARY, hlBytes, data.length);
	}
	
	/**
	 * Close a WebSocket connection
	 * @param conn Connection handle
	 * @param code Close status code (default: 1000 NORMAL)
	 * @param reason Optional close reason
	 */
	public function websocketClose(conn:Dynamic, code:Int = 1000, ?reason:String):Void {
		var reasonBytes = reason != null ? @:privateAccess reason.toUtf8() : null;
		CivetWebNative.websocketClose(conn, code, reasonBytes);
	}
}
