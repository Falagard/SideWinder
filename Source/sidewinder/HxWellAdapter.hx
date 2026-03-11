package sidewinder;

import hx.well.http.driver.socket.SocketDriver;
import hx.well.http.driver.socket.SocketDriverConfig;
import hx.well.http.driver.socket.SocketRequestParser;
import hx.well.http.Request as HxRequest;
import sys.net.Socket;
import sys.thread.Thread;
import sys.thread.Mutex;
import sidewinder.Router;
import snake.http.HTTPStatus;
import haxe.io.Bytes;

/**
 * Adapter for hxwell web server framework drivers.
 * Bridges hxwell's multi-threaded SocketDriver with SideWinder's single-threaded router loop.
 */
class HxWellAdapter implements IWebServer {
	private var driver:CustomSocketDriver;
	private var host:String;
	private var port:Int;
	private var running:Bool = false;
	private var requestQueue:Array<QueuedRequest> = [];
	private var queueMutex:Mutex = new Mutex();

	public function new(host:String, port:Int, ?directory:String) {
		this.host = host;
		this.port = port;

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

		var requests:Array<QueuedRequest> = null;
		queueMutex.acquire();
		if (requestQueue.length > 0) {
			requests = requestQueue.copy();
			requestQueue = [];
		}
		queueMutex.release();

		if (requests != null) {
			for (q in requests) {
				processQueuedRequest(q);
			}
		}
	}

	private function processQueuedRequest(q:QueuedRequest):Void {
		try {
			var swReq = convertRequest(q.hxRequest, q.socket);
			var swRes = createResponse(q.socket);

			var match = SideWinderRequestHandler.router.find(swReq.method, swReq.path);
			if (match != null) {
				swReq.params = match.params;
				SideWinderRequestHandler.router.handle(swReq, swRes, match.route);
			} else {
				// Static file handling fallback if router doesn't match
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

		// SideWinder Request structure
		var req:Router.Request = {
			method: hxReq.method,
			path: hxReq.path,
			headers: headers,
			query: hxReq.queries,
			params: new Map<String, String>(),
			body: body,
			jsonBody: null, 
			formBody: new haxe.ds.StringMap<String>(),
			cookies: new haxe.ds.StringMap<String>(),
			files: [],
			ip: hxReq.ip
		};

		// Copy cookies
		@:privateAccess {
			for (k in hxReq.cookies.keys()) {
				req.cookies.set(k, hxReq.cookies.get(k));
			}
		}

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
		queueMutex.acquire();
		requestQueue.push(q);
		queueMutex.release();
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
				socket.setTimeout(5);
				var hxReq = hx.well.http.driver.socket.SocketRequestParser.parseFromSocket(socket);
				
				// Handle body parsing if Content-Length is present
				var contentLen = hxReq.header("Content-Length");
				
				if (contentLen != null) {
					var len = Std.parseInt(contentLen);
					if (len > 0) {
						var input = new hx.well.http.driver.socket.SocketInput(socket);
						input.length = len;
						hx.well.http.driver.socket.SocketRequestParser.parseBody(hxReq, input);
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
