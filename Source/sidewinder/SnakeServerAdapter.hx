package sidewinder;

import snake.socket.*;
import sys.net.Host;
import sys.net.Socket;
import snake.http.*;
import sys.thread.Mutex;
import sidewinder.Router;

/**
 * Single-threaded adapter for the snake-server implementation.
 * Uses a request queue to ensure all Haxe request handling happens on a single thread.
 * 
 * Architecture:
 * - snake-server threads accept connections and enqueue requests
 * - handleRequest() processes queue one request at a time on main thread
 * - Thread-safe via mutex-protected queue
 */
class SnakeServerAdapter implements IWebServer {
	private var server:SideWinderServer;
	private var host:String;
	private var port:Int;
	private var running:Bool;

	// Single-threaded request queue
	private var requestQueue:Array<QueuedSnakeRequest>;
	private var queueMutex:Mutex;

	public static var instance:SnakeServerAdapter = null;

	/**
	 * Create a new snake-server adapter.
	 * @param host Server host address (e.g., "127.0.0.1")
	 * @param port Server port number (e.g., 8000)
	 * @param requestHandlerClass Request handler class (typically SideWinderRequestHandler)
	 * @param directory Optional directory for serving static files
	 */
	public function new(host:String, port:Int, requestHandlerClass:Class<BaseRequestHandler>, ?directory:String) {
		this.host = host;
		this.port = port;
		this.running = false;

		// Initialize request queue for single-threaded processing
		this.requestQueue = [];
		this.queueMutex = new Mutex();

		// Store singleton instance so request handler can access it
		SnakeServerAdapter.instance = this;

		// Create the snake-server instance
		this.server = new SideWinderServer(new Host(host), port, requestHandlerClass, true, directory);

		HybridLogger.info('[SnakeServerAdapter] Initialized for $host:$port (single-threaded mode)');
	}

	public function start():Void {
		if (!running) {
			// Server is already bound and activated in the constructor
			running = true;
			trace('[SnakeServerAdapter] Started on $host:$port');
		}
	}

	public function handleRequest():Void {
		if (running && server != null) {
			// First, let snake-server accept connections and enqueue
			server.handleRequest();

			// Then process all queued requests on main thread
			processQueue();
		}
	}

	/**
	 * Enqueue a request (called from snake-server thread).
	 */
	public function enqueueRequest(req:Router.Request, res:Router.Response, route:Router.Route):Void {
		queueMutex.acquire();
		try {
			requestQueue.push({
				request: req,
				response: res,
				route: route,
				timestamp: Date.now().getTime()
			});
			queueMutex.release();
		} catch (e:Dynamic) {
			queueMutex.release();
			throw e;
		}
	}

	/**
	 * Process all queued requests on main thread.
	 */
	private function processQueue():Void {
		var requests:Array<QueuedSnakeRequest> = null;

		queueMutex.acquire();
		try {
			if (requestQueue.length > 0) {
				requests = requestQueue.copy();
				requestQueue = [];
			}
			queueMutex.release();
		} catch (e:Dynamic) {
			queueMutex.release();
			throw e;
		}

		if (requests != null && requests.length > 0) {
			HybridLogger.debug('[SnakeServerAdapter] Processing ${requests.length} queued request(s)');

			for (queuedReq in requests) {
				try {
					SideWinderRequestHandler.router.handle(queuedReq.request, queuedReq.response, queuedReq.route);
					HybridLogger.debug('[SnakeServerAdapter] ${queuedReq.request.method} ${queuedReq.request.path}');
				} catch (e:Dynamic) {
					HybridLogger.error('[SnakeServerAdapter] Error processing request: $e');
				}
			}
		}
	}

	public function stop():Void {
		if (running) {
			running = false;

			// Clear any remaining queued requests
			queueMutex.acquire();
			try {
				if (requestQueue.length > 0) {
					HybridLogger.info('[SnakeServerAdapter] Clearing ${requestQueue.length} queued requests');
					requestQueue = [];
				}
				queueMutex.release();
			} catch (e:Dynamic) {
				queueMutex.release();
				throw e;
			}

			// Note: snake-server doesn't have explicit shutdown, but we mark as not running
			HybridLogger.info('[SnakeServerAdapter] Stopped');
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
 * Queued request entry for snake-server
 */
typedef QueuedSnakeRequest = {
	var request:Router.Request;
	var response:Router.Response;
	var route:Router.Route;
	var timestamp:Float;
}
