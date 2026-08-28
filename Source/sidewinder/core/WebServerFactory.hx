package sidewinder.core;

import sidewinder.adapters.HxWellAdapter;
import sidewinder.interfaces.IWebServer;
import sidewinder.interfaces.IslandManager;
import sidewinder.routing.Router;

/**
 * Web server implementation options.
 *
 * SIDEWINDER-SNAKE-REMOVAL-S1: `SnakeServer` and `CivetWeb` are gone.
 * CivetWeb's constructor had thrown unconditionally for some time, and the
 * snake-server backend was unreachable (`ServerConfig.useLime` is hardcoded
 * false). Neither was referenced by any consumer.
 */
enum WebServerType {
	HxWell;
}

/**
 * Factory for creating web server instances.
 */
class WebServerFactory {
	/**
	 * Create a web server instance.
	 *
	 * @param type Server implementation type
	 * @param host Server host address (e.g., "127.0.0.1")
	 * @param port Server port number (e.g., 8000)
	 * @param directory Optional directory for serving static files
	 * @return IWebServer instance
	 */
	public static function create(type:WebServerType, host:String, port:Int, ?directory:String, islandManager:IslandManager):IWebServer {
		return switch (type) {
			case HxWell:
				var adapter = new HxWellAdapter(host, port, directory, islandManager);
				adapter.router = Router.instance;
				adapter;
		};
	}

	/**
	 * Create a web server with the default implementation for this target.
	 */
	public static function createDefault(host:String, port:Int, ?directory:String, islandManager:IslandManager):IWebServer {
		return create(HxWell, host, port, directory, islandManager);
	}
}
