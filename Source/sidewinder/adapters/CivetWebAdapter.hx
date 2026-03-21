package sidewinder.adapters;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.interfaces.IWebSocketServer;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;

import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;


import sidewinder.native.CivetWebNative;
import sidewinder.native.CivetWebNative.CivetWebRequest;
import sidewinder.native.CivetWebNative.CivetWebResponse;


import haxe.io.Bytes;
#if hl
import hl.Bytes;
#end

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
#if hl
class CivetWebAdapter implements IWebServer implements IWebSocketServer {
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
	private var islandManager:IslandManager;

	public function new(host:String, port:Int, ?documentRoot:String, ?handler:Router.Request->SimpleResponse, islandManager:IslandManager) {
		this.host = host;
		this.port = port;
		this.running = false;
		this.serverHandle = null;
		this.documentRoot = documentRoot != null ? documentRoot : "./static";
		this.requestHandler = handler;
		this.islandManager = islandManager;

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

	public function handleRequest():Void {
		if (!running || serverHandle == null)
			return;

		try {
			var maxRequests = 100;
			var processed = 0;
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

				var requestId:Int = untyped req.id;
				processed++;

				try {
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

					var sessionId:Null<String> = null;
					var cookies = parseCookies(bytesToString(headersBytes));
					sessionId = cookies.get("session_id");

					islandManager.dispatch(sessionId, () -> {
						try {
							var response = handleNativeRequest(civetReq);
							var contentTypeBytes = stringToUtf8(response.contentType);
							var bodyStr = response.body != null ? response.body : "";
							var bodyBytesRef = haxe.io.Bytes.ofString(bodyStr);
							var respBodyBytes = @:privateAccess bodyBytesRef.b;
							CivetWebNative.pushResponse(serverHandle, requestId, response.statusCode, contentTypeBytes, respBodyBytes, bodyBytesRef.length);
						} catch (e:Dynamic) {
							HybridLogger.error('[CivetWebAdapter] Island processing error: $e');
							var errorMsg = "Internal Server Error";
							var errorBytes = haxe.io.Bytes.ofString(errorMsg);
							var errorContentType = stringToUtf8("text/plain");
							var errorBody = @:privateAccess errorBytes.b;
							CivetWebNative.pushResponse(serverHandle, requestId, 500, errorContentType, errorBody, errorBytes.length);
						}
					});
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] Error dispatching request: $e');
				}
			}
		} catch (e:Dynamic) {
			HybridLogger.error('[CivetWebAdapter] Error in polling loop: $e\n' + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
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
					switch (evt.type) {
						case 0: websocketHandler.onConnect();
						case 1: websocketHandler.onReady(evt.conn);
						case 2:
							var dataBytes:hl.Bytes = evt.data;
							websocketHandler.onData(evt.conn, evt.flags, dataBytes, evt.dataLength);
						case 3: websocketHandler.onClose(evt.conn);
					}
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] Error handling WebSocket event: ' + e);
				}
			}
		}
	}

	private function stringToUtf8(s:String):hl.Bytes {
		if (s == null) return null;
		var b = haxe.io.Bytes.ofString(s);
		return @:privateAccess b.b;
	}

	private function bytesToString(b:hl.Bytes):String {
		if (b == null) return "";
		return @:privateAccess String.fromUTF8(b);
	}

	private function bytesToStringWithLen(b:hl.Bytes, len:Int):String {
		if (b == null || len <= 0) return "";
		var hxBytes = b.toBytes(len);
		return hxBytes.toString();
	}

	private function handleNativeRequest(reqData:Dynamic):CivetWebResponse {
		try {
			var req:CivetWebRequest = cast reqData;
			var headers = parseHeaders(req.headers);
			var pathOnly = req.uri.split("?")[0];
			if (corsEnabled && req.method == "OPTIONS") {
				return {statusCode: 200, contentType: "text/plain", body: "", bodyLength: 0};
			}
			var contentType = headers.get("Content-Type");
			if (contentType == null) contentType = headers.get("content-type");
			var jsonBody:Dynamic = null;
			var formBody = new haxe.ds.StringMap<String>();
			var files:Array<UploadedFile> = [];
			if (contentType != null && contentType.indexOf("application/json") != -1) {
				try { jsonBody = haxe.Json.parse(req.body); } catch (e:Dynamic) {}
			} else if (contentType != null && contentType.indexOf("application/x-www-form-urlencoded") != -1) {
				for (pair in req.body.split("&")) {
					var kv = pair.split("=");
					if (kv.length == 2) formBody.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
				}
			} else if (contentType != null && contentType.indexOf("multipart/form-data") != -1) {
				var multipartData = MultipartParser.parseMultipart(req.body, contentType);
				files = multipartData.files;
				formBody = multipartData.fields;
			}
			var cookies = parseCookies(headers.get("Cookie"));
			var sessionId = cookies.get("session_id");
			var newSession = false;
			if (sessionId == null) {
				sessionId = generateSessionId();
				cookies.set("session_id", sessionId);
				newSession = true;
			}
			sessionStore.set(sessionId, Date.now().getTime());
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
			var response:SimpleResponse;
			if (requestHandler != null) {
				response = requestHandler(routerReq);
			} else {
				response = {statusCode: 404, contentType: "text/plain", body: "Not Found", headers: new Map<String, String>()};
			}
			if (corsEnabled) {
				if (!response.headers.exists("Access-Control-Allow-Origin")) response.headers.set("Access-Control-Allow-Origin", "*");
				if (!response.headers.exists("Access-Control-Allow-Methods")) response.headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
				if (!response.headers.exists("Access-Control-Allow-Headers")) response.headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
			}
			if (newSession) response.headers.set("Set-Cookie", 'session_id=$sessionId; Path=/; HttpOnly');
			var respContentType = response.headers.get("Content-Type");
			if (respContentType == null) respContentType = "text/html; charset=utf-8";
			return {statusCode: response.statusCode, contentType: respContentType, body: response.body != null ? response.body : "", bodyLength: response.body != null ? response.body.length : 0};
		} catch (e:Dynamic) {
			return {statusCode: 500, contentType: "text/plain", body: "Internal Server Error", bodyLength: 21};
		}
	}

	private function parseHeaders(headersStr:String):Map<String, String> {
		var result = new Map<String, String>();
		if (headersStr == null || headersStr == "") return result;
		var lines = headersStr.split("\n");
		for (line in lines) {
			if (line == "") continue;
			var colonPos = line.indexOf(":");
			if (colonPos > 0) result.set(line.substr(0, colonPos), StringTools.trim(line.substr(colonPos + 1)));
		}
		return result;
	}

	private function parseQueryString(qs:String):Map<String, String> {
		var result = new Map<String, String>();
		if (qs == null || qs == "") return result;
		var pairs = qs.split("&");
		for (pair in pairs) {
			var kv = pair.split("=");
			if (kv.length >= 2) result.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
			else if (kv.length == 1) result.set(StringTools.urlDecode(kv[0]), "");
		}
		return result;
	}

	private function parseCookies(cookieHeader:String):haxe.ds.StringMap<String> {
		var cookies = new haxe.ds.StringMap<String>();
		if (cookieHeader == null || cookieHeader == "") return cookies;
		for (pair in cookieHeader.split(";")) {
			var kv = pair.split("=");
			if (kv.length == 2) cookies.set(StringTools.trim(kv[0]), StringTools.trim(kv[1]));
		}
		return cookies;
	}

	private function generateSessionId():String {
		return Std.string(Math.floor(Math.random() * 1000000000)) + "_" + Std.string(Date.now().getTime());
	}

	public function stop():Void {
		if (running && serverHandle != null) {
			try {
				CivetWebNative.stop(serverHandle);
				running = false;
				HybridLogger.info('[CivetWebAdapter] Server stopped');
			} catch (e:Dynamic) {}
		}
	}

	public function getHost():String { return host; }
	public function getPort():Int { return port; }
	public function isRunning():Bool { return running; }
	public function setWebSocketHandler(handler:IWebSocketHandler):Void { this.websocketHandler = handler; }
	public function websocketSendText(conn:Dynamic, text:String):Void {
		var bytes = stringToUtf8(text);
		CivetWebNative.websocketSend(cast conn, WebSocketOpcode.TEXT, bytes, text.length);
	}
	public function websocketSendBinary(conn:Dynamic, data:haxe.io.Bytes):Void {
		var hlBytes = @:privateAccess data.b;
		CivetWebNative.websocketSend(cast conn, WebSocketOpcode.BINARY, hlBytes, data.length);
	}
	public function websocketClose(conn:Dynamic, code:Int = 1000, ?reason:String):Void {
		var reasonBytes = reason != null ? stringToUtf8(reason) : null;
		CivetWebNative.websocketClose(cast conn, code, reasonBytes);
	}
}
#else
class CivetWebAdapter implements IWebServer implements IWebSocketServer {
	public function new(host:String, port:Int, ?documentRoot:String, ?handler:Dynamic, islandManager:Dynamic) {}
	public function start():Void {}
	public function stop():Void {}
	public function handleRequest():Void {}
	public function getHost():String return "";
	public function getPort():Int return 0;
	public function isRunning():Bool return false;
	public function setWebSocketHandler(handler:Dynamic):Void {}
	public function websocketSendText(conn:Dynamic, text:String):Void {}
	public function websocketSendBinary(conn:Dynamic, data:haxe.io.Bytes):Void {}
	public function websocketClose(conn:Dynamic, code:Int = 1000, ?reason:String):Void {}
}
#end
