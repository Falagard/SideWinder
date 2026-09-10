package sidewinder.routing;

// SIDEWINDER-SNAKE-REMOVAL-S1.
//
// Holds the process-wide router and the HTTP behaviour flags that used to live
// as statics on `SideWinderRequestHandler`.
//
// That class was a snake-server `SimpleHTTPRequestHandler` subclass -- 415 lines
// of a second HTTP server implementation. It had been dead as a server for some
// time (`ServerConfig.useLime` is hardcoded false, so `WebServerFactory` always
// selects the HxWell transport), but it was still alive as a *namespace*:
// `ServerBootstrap` and `StackServerSDK` both read `SideWinderRequestHandler.router`.
//
// Four statics were therefore keeping an entire unused HTTP stack -- and the
// snake-server dependency -- linked into every build. They live here now, and
// `SideWinderRequestHandler`, `SnakeServerAdapter`, `SideWinderServer`,
// `CivetWebAdapter` and `CivetWebNative` are gone.
class RouterRegistry {
	/** The process-wide router that AutoRouter registers routes on. */
	public static var router:Router = Router.instance;

	/** Emit permissive CORS headers on responses. */
	public static var corsEnabled:Bool = false;

	/** Allow cache headers on static responses. */
	public static var cacheEnabled:Bool = true;

	/** Suppress per-request access logging. */
	public static var silent:Bool = false;
}
