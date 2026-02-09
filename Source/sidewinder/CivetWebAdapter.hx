package sidewinder;

import sidewinder.native.CivetWebNative;
import sidewinder.native.CivetWebNative.CivetWebRequest;
import sidewinder.native.CivetWebNative.CivetWebResponse;
import sidewinder.Router;
import sidewinder.IWebSocketHandler;
import haxe.io.Bytes;
import hl.Bytes;

typedef SimpleResponse = {
	var statusCode:Int;
	var contentType:String;
	var body:String;
	var headers:Map<String, String>;
};

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
	private var requestHandler:Router.Request->SimpleResponse;
	private var websocketHandler:IWebSocketHandler;
	private var corsEnabled:Bool = true;
	private var sessionStore:Map<String, Float> = new Map();
	private var pollCounter:Int = 0;

	/**
	 * Create a new CivetWeb adapter.
	 * @param host Server host address (e.g., "127.0.0.1")
	 * @param port Server port number (e.g., 8000)
	 * @param documentRoot Optional document root for serving static files
	 */
	public function new(host:String, port:Int, ?documentRoot:String, ?handler:Router.Request->SimpleResponse) {
		this.host = host;
		this.port = port;
		this.running = false;
		this.serverHandle = null;
		this.documentRoot = documentRoot != null ? documentRoot : "./static";
		this.requestHandler = handler;

		HybridLogger.info('[CivetWebAdapter] Initialized for $host:$port');
		HybridLogger.info('[CivetWebAdapter] Document root: ${this.documentRoot}');

		// Create native server instance
		var hostBytes = stringToUtf8(host);
		var docRootBytes = stringToUtf8(this.documentRoot);

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
			try {
				var started = CivetWebNative.start(serverHandle);
				if (started) {
					running = true;
					HybridLogger.info('[CivetWebAdapter] Server started on $host:$port');
					HybridLogger.info('[CivetWebAdapter] Access at http://$host:$port');
					HybridLogger.info('[CivetWebAdapter] Using polling architecture - call handleRequest() in main loop');
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
	 * Poll for pending requests and process them on the main thread.
	 * MUST be called regularly in the main loop for the server to function.
	 */
	public function handleRequest():Void {
		if (!running || serverHandle == null)
			return;

		try {
			// Poll for pending requests from C layer
			// We process all available requests in the queue
			var maxRequests = 100; // Limit per frame to prevent freezing
			var processed = 0;

			// Debug: Log periodically
			pollCounter++;
			if (pollCounter % 60 == 0) {
				HybridLogger.debug('[CivetWebAdapter] Polling...');
			}

			while (processed < maxRequests) {
				var req:Dynamic = null;
				try {
					req = CivetWebNative.pollRequest(serverHandle);
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] pollRequest threw: ' + e + '\n' + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
					throw e;
				}

				if (req == null)
					break;

				HybridLogger.debug('[CivetWebAdapter] Got request object');

				var requestId:Int = 0;
				try {
					requestId = untyped req.id;
					HybridLogger.debug('[CivetWebAdapter] Req ID: ' + requestId);
					var rawMethod:hl.Bytes = untyped req.method;
					HybridLogger.debug('[CivetWebAdapter] Req Method: ' + bytesToString(rawMethod));
					var rawUri:hl.Bytes = untyped req.uri;
					HybridLogger.debug('[CivetWebAdapter] Req URI: ' + bytesToString(rawUri));
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] Error accessing fields: ' + e);
					throw e; // Rethrow to main catch
				}

				processed++;

				try {
					// Convert dynamic request to CivetWebRequest
					// Native fields are hl.Bytes, need conversion to String
					var uriBytes:hl.Bytes = untyped req.uri;
					var methodBytes:hl.Bytes = untyped req.method;
					var bodyBytes:hl.Bytes = untyped req.body;
					var queryStringBytes:hl.Bytes = untyped req.queryString;
					var remoteAddrBytes:hl.Bytes = untyped req.remoteAddr;
					var headersBytes:hl.Bytes = untyped req.headers;
					var bodyLength:Int = untyped req.bodyLength;

					var civetReq:CivetWebRequest = {
						uri: bytesToString(uriBytes),
						method: bytesToString(methodBytes),
						body: bytesToStringWithLen(bodyBytes, bodyLength),
						bodyLength: bodyLength,
						queryString: bytesToString(queryStringBytes),
						remoteAddr: bytesToString(remoteAddrBytes),
						headers: bytesToString(headersBytes)
					};

					// Process request on main thread
					var response = handleNativeRequest(civetReq);

					// Push response back to C layer
					var contentTypeBytes = stringToUtf8(response.contentType);
					var bodyBytesRef = haxe.io.Bytes.ofString(response.body);
					var respBodyBytes = @:privateAccess bodyBytesRef.b;
					CivetWebNative.pushResponse(serverHandle, requestId, response.statusCode, contentTypeBytes, respBodyBytes, bodyBytesRef.length);
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] Error handling request: $e');

					// Push error response
					var errorMsg = "Internal Server Error";
					var errorBytes = haxe.io.Bytes.ofString(errorMsg);
					var errorContentType = stringToUtf8("text/plain");
					var errorBody = @:privateAccess errorBytes.b;
					CivetWebNative.pushResponse(serverHandle, requestId, 500, errorContentType, errorBody, errorBytes.length);
				}
			}
		} catch (e:Dynamic) {
			HybridLogger.error('[CivetWebAdapter] Error in polling loop: $e\n' + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
		// Poll for WebSocket events
		if (websocketHandler != null) {
			var maxWsEvents = 100;
			var wsProcessed = 0;

			while (wsProcessed < maxWsEvents) {
				var evt:Dynamic = null;

				try {
					evt = CivetWebNative.pollWebSocketEvent(serverHandle);
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] pollWebSocketEvent threw: ' + e);
					break;
				}
				if (evt == null)
					break;
				wsProcessed++;
				try {
					// Event types: 0=Connect, 1=Ready, 2=Data, 3=Close
					// evt fields: type, conn, flags, data, dataLength
					switch (evt.type) {
						case 0: // Connect
							websocketHandler.onConnect();
						case 1: // Ready
							// Cast the conn to Dynamic/Abstract expected by handler
							websocketHandler.onReady(evt.conn);
						case 2: // Data
							var dataBytes:hl.Bytes = evt.data;
							websocketHandler.onData(evt.conn, evt.flags, dataBytes, evt.dataLength);
						case 3: // Close
							websocketHandler.onClose(evt.conn);
					}
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] Error handling WebSocket event: ' + e);
				}
			}
		}
	}

	private function stringToUtf8(s:String):hl.Bytes {
		if (s == null)
			return null;
		var b = haxe.io.Bytes.ofString(s);
		return @:privateAccess b.b;
	}

	private function bytesToString(b:hl.Bytes):String {
		if (b == null)
			return "";
		return @:privateAccess String.fromUTF8(b);
	}

	private function bytesToStringWithLen(b:hl.Bytes, len:Int):String {
		if (b == null || len <= 0)
			return "";
		var hxBytes = b.toBytes(len);
		return hxBytes.toString();
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
			if (contentType == null)
				contentType = headers.get("content-type");

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
			var response:SimpleResponse;
			if (requestHandler != null) {
				response = requestHandler(routerReq);
				HybridLogger.debug('[CivetWebAdapter] ${req.method} ${pathOnly} -> ${response.statusCode}');
			} else {
				response = {
					statusCode: 404,
					contentType: "text/plain",
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
			if (respContentType == null)
				respContentType = "text/html; charset=utf-8";

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
		if (headersStr == null || headersStr == "")
			return result;

		var lines = headersStr.split("\n");
		for (line in lines) {
			if (line == "")
				continue;
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
		if (qs == null || qs == "")
			return result;

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
		if (cookieHeader == null || cookieHeader == "")
			return cookies;

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
		HybridLogger.info('[CivetWebAdapter] WebSocket handler registered');
	}

	/**
	 * Send data through a WebSocket connection
	 * @param conn Connection handle
	 * @param text Text data to send
	 * @return Bytes sent or -1 on error
	 */
	public function websocketSendText(conn:hl.Bytes, text:String):Int {
		var bytes = stringToUtf8(text);
		return CivetWebNative.websocketSend(conn, WebSocketOpcode.TEXT, bytes, text.length);
	}

	/**
	 * Send binary data through a WebSocket connection
	 * @param conn Connection handle
	 * @param data Binary data to send
	 * @return Bytes sent or -1 on error
	 */
	public function websocketSendBinary(conn:hl.Bytes, data:haxe.io.Bytes):Int {
		var hlBytes = @:privateAccess data.b;
		return CivetWebNative.websocketSend(conn, WebSocketOpcode.BINARY, hlBytes, data.length);
	}

	/**
	 * Close a WebSocket connection
	 * @param conn Connection handle
	 * @param code Close status code (default: 1000 NORMAL)
	 * @param reason Optional close reason
	 */
	public function websocketClose(conn:hl.Bytes, code:Int = 1000, ?reason:String):Void {
		var reasonBytes = reason != null ? stringToUtf8(reason) : null;
		CivetWebNative.websocketClose(conn, code, reasonBytes);
	}
}
