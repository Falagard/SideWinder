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

	// Logic islands for parallel processing
	private var islandManager:IslandManager;

	public static var instance:SnakeServerAdapter = null;

	/**
	 * Create a new snake-server adapter.
	 * @param host Server host address (e.g., "127.0.0.1")
	 * @param port Server port number (e.g., 8000)
	 * @param requestHandlerClass Request handler class (typically SideWinderRequestHandler)
	 * @param directory Optional directory for serving static files
	 */
	public function new(host:String, port:Int, requestHandlerClass:Class<BaseRequestHandler>, ?directory:String, numIslands:Int = 4) {
		this.host = host;
		this.port = port;
		this.running = false;

		// Initialize island manager
		this.islandManager = new IslandManager(numIslands);

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
			// Let snake-server accept connections and trigger enqueueRequest
			server.handleRequest();
		}
	}

	/**
	 * Enqueue a request (called from snake-server thread).
	 */
	public function enqueueRequest(req:Router.Request, res:Router.Response, route:Router.Route):Void {
		var sessionId = req.cookies.get("session_id");
		islandManager.dispatch(sessionId, () -> {
			try {
				SideWinderRequestHandler.router.handle(req, res, route);
				HybridLogger.debug('[SnakeServerAdapter] ${req.method} ${req.path} (Island)');
			} catch (e:Dynamic) {
				HybridLogger.error('[SnakeServerAdapter] Error processing request on island: $e');
			}
		});
	}

	public function stop():Void {
		if (running) {
			running = false;
			islandManager.shutdown();
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
