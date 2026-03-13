package sidewinder.core;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.adapters.HxWellAdapter;
import sidewinder.adapters.CivetWebAdapter;
import sidewinder.adapters.CivetWebAdapter.SimpleResponse;
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
				// CivetWeb uses direct callback with SimpleResponse
				// We bridge the async Router to sync CivetWeb response
				var handler = function(req:Request):SimpleResponse {
					var buffered = new BufferedResponse();
					// Use SideWinderRequestHandler logic if possible, or direct router find/handle
					var match = SideWinderRequestHandler.router.find(req.method, req.path);
					if (match != null) {
						// Important: Copy matched params to request
						req.params = match.params;
						// Note: This loses static file handling from SideWinderRequestHandler base class
						// TODO: Replicate static file handling if needed for CivetWeb
						try {
							SideWinderRequestHandler.router.handle(req, buffered, cast match.route);
						} catch (e:Dynamic) {
							buffered.sendError(snake.http.HTTPStatus.INTERNAL_SERVER_ERROR);
						}
					} else {
						buffered.sendError(snake.http.HTTPStatus.NOT_FOUND);
					}
					return buffered.toSimpleResponse();
				};
				return new CivetWebAdapter(host, port, directory, handler, islandManager);

			case HxWell:
				return new HxWellAdapter(host, port, directory, islandManager);
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
		// Default to SnakeServer for hl target, could be extended for other targets
		#if cpp
		trace("[WebServerFactory] Using CivetWeb for cpp target");
		return create(CivetWeb, host, port, requestHandlerClass, directory, islandManager);
		#else
		trace("[WebServerFactory] Using SnakeServer (default)");
		return create(SnakeServer, host, port, requestHandlerClass, directory, islandManager);
		#end
	}
}
