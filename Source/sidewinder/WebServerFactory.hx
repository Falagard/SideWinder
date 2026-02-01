package sidewinder;

import snake.server.BaseRequestHandler;

/**
 * Web server implementation options.
 */
enum WebServerType {
	SnakeServer;
	CivetWeb;
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
	public static function create(
		type:WebServerType, 
		host:String, 
		port:Int, 
		?requestHandlerClass:Class<BaseRequestHandler>,
		?directory:String
	):IWebServer {
		return switch (type) {
			case SnakeServer:
				if (requestHandlerClass == null) {
					throw "SnakeServer requires a requestHandlerClass";
				}
				new SnakeServerAdapter(host, port, requestHandlerClass, directory);
				
			case CivetWeb:
				// CivetWeb uses direct callback, not a handler class
				// We'll use SideWinderRequestHandler.handleRequest directly
				var handler = function(req:Router.Request):Router.Response {
					return SideWinderRequestHandler.router.route(req);
				};
				new CivetWebAdapter(host, port, directory, handler);
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
	public static function createDefault(
		host:String, 
		port:Int, 
		?requestHandlerClass:Class<BaseRequestHandler>,
		?directory:String
	):IWebServer {
		// Default to SnakeServer for hl target, could be extended for other targets
		#if cpp
		trace("[WebServerFactory] Using CivetWeb for cpp target");
		return create(CivetWeb, host, port, requestHandlerClass, directory);
		#else
		trace("[WebServerFactory] Using SnakeServer (default)");
		return create(SnakeServer, host, port, requestHandlerClass, directory);
		#end
	}
}
