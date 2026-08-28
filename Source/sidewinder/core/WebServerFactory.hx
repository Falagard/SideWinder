package sidewinder.core;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.adapters.HxWellAdapter;
import sidewinder.adapters.SnakeServerAdapter;
import sidewinder.interfaces.IWebServer;
import sidewinder.interfaces.IslandManager;
import sidewinder.routing.Router;
import sidewinder.routing.SideWinderRequestHandler;
import sidewinder.data.BufferedResponse;
import sidewinder.logging.HybridLogger;
import snake.socket.BaseRequestHandler;

/**
 * Web server implementation options.
 */
enum WebServerType {
	SnakeServer;
	CivetWeb;
	HxWell;
}

/**
 * Factory for creating web server instances.
 * Provides a centralized way to switch between different HTTP server implementations.
 */
class WebServerFactory {
	/**
	 * Create a web server instance.
	 * 
	 * @param type Server implementation type
	 * @param host Server host address (e.g., "127.0.0.1")
	 * @param port Server port number (e.g., 8000)
	 * @param requestHandlerClass Request handler class (for snake-server)
	 * @param directory Optional directory for serving static files
	 * @return IWebServer instance
	 */
	public static function create(type:WebServerType, host:String, port:Int, ?requestHandlerClass:Class<BaseRequestHandler>, ?directory:String,
			islandManager:IslandManager):IWebServer {
		return switch (type) {
			case SnakeServer:
				if (requestHandlerClass == null) {
					throw "SnakeServer requires a requestHandlerClass";
				}
				new SnakeServerAdapter(host, port, requestHandlerClass, directory, islandManager);

			case CivetWeb:
				// SIDEWINDER-CORE-HYGIENE-S1: kept as an explicit runtime error rather
				// than silently falling back, but createDefault() no longer routes any
				// target here -- see below.
				throw "CivetWeb support is disabled in this build; use WebServerType.HxWell";

			case HxWell:
				var adapter = new HxWellAdapter(host, port, directory, islandManager);
				adapter.router = Router.instance;
				return adapter;
		};
	}

	/**
	 * Create a web server with automatic selection based on compilation target.
	 * 
	 * @param host Server host address
	 * @param port Server port number
	 * @param requestHandlerClass Request handler class (for snake-server)
	 * @param directory Optional directory for serving static files
	 * @return IWebServer instance
	 */
	public static function createDefault(host:String, port:Int, ?requestHandlerClass:Class<BaseRequestHandler>, ?directory:String,
			islandManager:IslandManager):IWebServer {
		// SIDEWINDER-CORE-HYGIENE-S1: this used to select CivetWeb on cpp -- a backend
		// whose constructor unconditionally throws, so every cpp consumer got a server
		// that compiled and then died at startup. cpp now gets the HxWell transport,
		// which is the only backend proven to run on that target.
		#if cpp
		trace("[WebServerFactory] Using HxWell for cpp target");
		return create(HxWell, host, port, requestHandlerClass, directory, islandManager);
		#else
		trace("[WebServerFactory] Using SnakeServer (default)");
		return create(SnakeServer, host, port, requestHandlerClass, directory, islandManager);
		#end
	}
}
