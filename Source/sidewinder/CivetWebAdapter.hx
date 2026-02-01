package sidewinder;

import sidewinder.native.CivetWebNative;
import sidewinder.native.CivetWebNative.CivetWebRequest;
import sidewinder.native.CivetWebNative.CivetWebResponse;
import sidewinder.Router;
import haxe.io.Bytes;
import sys.thread.Mutex;

/**
 * Single-threaded adapter for CivetWeb HTTP server using HashLink native bindings.
 * Uses a request queue to ensure all Haxe request handling happens on a single thread.
 * 
 * Architecture:
 * - CivetWeb C threads accept connections and enqueue requests
 * - handleRequest() processes queue one request at a time
 * - Thread-safe via mutex-protected queue
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
	
	// Single-threaded request queue
	private var requestQueue:Array<QueuedRequest>;
	private var queueMutex:Mutex;
	
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
		
		// Initialize request queue for single-threaded processing
		this.requestQueue = [];
		this.queueMutex = new Mutex();
		
		HybridLogger.info('[CivetWebAdapter] Initialized for $host:$port (single-threaded mode)');
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
			// Define callback that enqueues requests instead of processing immediately
			var callback = function(req:Dynamic):CivetWebResponse {
				return enqueueRequest(req);
			};
			
			try {
				var started = CivetWebNative.start(serverHandle, callback);
				if (started) {
					running = true;
					HybridLogger.info('[CivetWebAdapter] Server started on $host:$port (single-threaded)');
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
	 * Enqueue an incoming request (called from C thread).
	 * Returns immediate response to avoid blocking C thread.
	 */
	private function enqueueRequest(reqData:Dynamic):CivetWebResponse {
		queueMutex.acquire();
		try {
			var req:CivetWebRequest = cast reqData;
			
			// Store request in queue
			requestQueue.push({
				request: req,
				timestamp: Date.now().getTime()
			});
			
			// Return immediate "processing" response
			return {
				statusCode: 202,
				contentType: "text/plain",
				body: "Processing",
				bodyLength: 10
			};
		} catch (e:Dynamic) {
			HybridLogger.error('[CivetWebAdapter] Error enqueueing request: $e');
			return {
				statusCode: 500,
				contentType: "text/plain",
				body: "Error",
				bodyLength: 5
			};
		} finally {
			queueMutex.release();
		}
	}
	
	public function handleRequest():Void {
		if (!running) return;
		
		// Process all queued requests on main thread
		var requests:Array<QueuedRequest> = null;
		
		queueMutex.acquire();
		try {
			if (requestQueue.length > 0) {
				requests = requestQueue.copy();
				requestQueue = [];
			}
		} finally {
			queueMutex.release();
		}
		
		if (requests != null && requests.length > 0) {
			HybridLogger.debug('[CivetWebAdapter] Processing ${requests.length} queued request(s)');
			
			for (queuedReq in requests) {
				try {
					processRequest(queuedReq.request);
				} catch (e:Dynamic) {
					HybridLogger.error('[CivetWebAdapter] Error processing request: $e');
				}
			}
		}
	}
	
	/**
	 * Process a single request (on main thread).
	 */
	private function processRequest(req:CivetWebRequest):Void {
		try {
			// Parse multipart/form-data for file uploads
			var files:Array<UploadedFile> = [];
			var formBody = new haxe.ds.StringMap<String>();
			var jsonBody:Dynamic = null;
			var body = req.body;
			
			// TODO: Get content-type from request headers when available
			// For now, detect multipart from body content
			if (body.indexOf("Content-Disposition") != -1 && body.indexOf("boundary") != -1) {
				// Try to parse as multipart
				var multipartData = MultipartParser.parseMultipart(body, "multipart/form-data; boundary=" + extractBoundaryFromBody(body));
				files = multipartData.files;
				formBody = multipartData.fields;
			}
			
			// Convert native request to Router.Request
			var routerReq:Router.Request = {
				method: req.method,
				path: req.uri,
				query: parseQueryString(req.queryString),
				headers: new Map<String, String>(),
				body: req.body,
				jsonBody: jsonBody,
				formBody: formBody,
				params: new Map<String, String>(),
				cookies: new haxe.ds.StringMap<String>(),
				files: files,
				ip: req.remoteAddr
			};
			
			// Call the request handler if set
			var response:Router.Response;
			if (requestHandler != null) {
				response = requestHandler(routerReq);
				HybridLogger.debug('[CivetWebAdapter] ${req.method} ${req.uri} -> ${response.statusCode}');
			} else {
				response = {
					statusCode: 404,
					body: "Not Found",
					headers: new Map<String, String>()
				};
			}
			
			// Note: Response sent via immediate 202 in enqueueRequest
			// For true async, would need connection tracking and deferred sends
		} catch (e:Dynamic) {
			HybridLogger.error('[CivetWebAdapter] Error processing request: $e');
		}
	}
	
	/**
	 * Extract boundary from multipart body (fallback method)
	 */
	private function extractBoundaryFromBody(body:String):String {
		var lines = body.split("\n");
		if (lines.length > 0) {
			var firstLine = StringTools.trim(lines[0]);
			if (StringTools.startsWith(firstLine, "--")) {
				return firstLine.substr(2);
			}
		}
		return "boundary";
	}
	
	/**
	 * Handle incoming HTTP requests from CivetWeb
	 */
	private function handleNativeRequest(reqData:Dynamic):CivetWebResponse {
		try {
			// Convert native request to Router.Request
			var req:CivetWebRequest = cast reqData;
			
			var routerReq:Router.Request = {
				method: req.method,
				path: req.uri,
				query: parseQueryString(req.queryString),
				headers: new Map<String, String>(),
				body: req.body,
				ip: req.remoteAddr
			};
			
			// Call the request handler if set, otherwise return 404
			var response:Router.Response;
			if (requestHandler != null) {
				response = requestHandler(routerReq);
			} else {
				response = {
					statusCode: 404,
					body: "Not Found",
					headers: new Map<String, String>()
				};
			}
			
			// Convert Router.Response to CivetWebResponse
			var contentType = response.headers.get("Content-Type");
			if (contentType == null) contentType = "text/html; charset=utf-8";
	
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

	public function stop():Void {
		if (running && serverHandle != null) {
			try {
				CivetWebNative.stop(serverHandle);
				running = false;
				
				// Clear any remaining queued requests
				queueMutex.acquire();
				try {
					if (requestQueue.length > 0) {
						HybridLogger.info('[CivetWebAdapter] Clearing ${requestQueue.length} queued requests');
						requestQueue = [];
					}
				} finally {
					queueMutex.release();
				}
				
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
}

/**
 * Request queue entry
 */
typedef QueuedRequest = {
	var request:CivetWebRequest;
	var timestamp:Float;
}
