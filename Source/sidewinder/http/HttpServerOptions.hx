package sidewinder.http;

// SIDEWINDER-CORE-DECOUPLING-S1 (Tasks D + K).
//
// Default, self-validating implementation of IHttpServerOptions.
//
// Task K background -- the worker-pool exhaustion defect this class exists to
// make impossible:
//
//   HxWell's `AbstractDriverConfig.poolSize` defaults to 10, and
//   `SocketWebSocketHandler.upgrade()` blocks its worker for the whole life of
//   the connection. So N concurrent WebSocket clients permanently consume N
//   workers. At N == poolSize the server stops answering HTTP *and* stops
//   accepting new WebSocket connections -- a total deadlock, reproduced at
//   exactly 10 clients in FOOTNOTE-PEDAL-SERVER-ARCH-EVAL.
//
// Two mitigations, applied together:
//
//   1. `workerPoolSize` is validated against
//      `maxWebSocketConnections + httpWorkerHeadroom` and REJECTED at
//      construction if it cannot satisfy it. Unsafe configuration cannot be
//      constructed, let alone shipped silently.
//   2. `maxWebSocketConnections` is enforced at admission time by
//      `WebSocketAdmissionPolicy`, so WebSockets can never eat the HTTP
//      headroom even if a client floods upgrades.
class HttpServerOptions implements IHttpServerOptions {
	public var host(default, null):String;
	public var port(default, null):Int;
	public var maxHeaderSize(default, null):Int;
	public var maxUrlLength(default, null):Int;
	public var maxRequestBodySize(default, null):Int;
	public var maxWebSocketMessageSize(default, null):Int;
	public var workerPoolSize(default, null):Int;
	public var maxWebSocketConnections(default, null):Int;
	public var httpWorkerHeadroom(default, null):Int;
	public var maxConnections(default, null):Int;

	public static inline var DEFAULT_MAX_HEADER_SIZE = 32768;
	public static inline var DEFAULT_MAX_URL_LENGTH = 8192;
	public static inline var DEFAULT_MAX_REQUEST_BODY_SIZE = 10485760; // 10 MB
	public static inline var DEFAULT_MAX_WS_MESSAGE_SIZE = 65536; // 64 KB

	/**
	 * Default WebSocket ceiling. Chosen to cover the "1-10 mobile clients"
	 * target in the FootNote pedal design with margin, while keeping the
	 * implied worker pool small enough that hxcpp GC pause time (which scales
	 * with registered thread count) stays modest on an SBC.
	 */
	public static inline var DEFAULT_MAX_WS_CONNECTIONS = 16;

	/** Workers reserved for HTTP once the WebSocket ceiling is reached. */
	public static inline var DEFAULT_HTTP_WORKER_HEADROOM = 8;

	public static inline var DEFAULT_MAX_CONNECTIONS = 512;

	/**
	 * The smallest worker pool that can safely serve `maxWebSocketConnections`
	 * long-lived WebSockets while keeping `httpWorkerHeadroom` workers free
	 * for HTTP.
	 */
	public static function minimumSafeWorkerPoolSize(maxWebSocketConnections:Int, httpWorkerHeadroom:Int):Int {
		return maxWebSocketConnections + httpWorkerHeadroom;
	}

	public function new(host:String, port:Int, ?options:HttpServerOptionsInit) {
		if (host == null || host == "")
			throw "HttpServerOptions: host must be a non-empty bind address";
		if (port <= 0 || port > 65535)
			throw 'HttpServerOptions: port out of range: $port';

		this.host = host;
		this.port = port;

		var init:HttpServerOptionsInit = options == null ? {} : options;

		this.maxHeaderSize = init.maxHeaderSize != null ? init.maxHeaderSize : DEFAULT_MAX_HEADER_SIZE;
		this.maxUrlLength = init.maxUrlLength != null ? init.maxUrlLength : DEFAULT_MAX_URL_LENGTH;
		this.maxRequestBodySize = init.maxRequestBodySize != null ? init.maxRequestBodySize : DEFAULT_MAX_REQUEST_BODY_SIZE;
		this.maxWebSocketMessageSize = init.maxWebSocketMessageSize != null ? init.maxWebSocketMessageSize : DEFAULT_MAX_WS_MESSAGE_SIZE;
		this.maxWebSocketConnections = init.maxWebSocketConnections != null ? init.maxWebSocketConnections : DEFAULT_MAX_WS_CONNECTIONS;
		this.httpWorkerHeadroom = init.httpWorkerHeadroom != null ? init.httpWorkerHeadroom : DEFAULT_HTTP_WORKER_HEADROOM;
		this.maxConnections = init.maxConnections != null ? init.maxConnections : DEFAULT_MAX_CONNECTIONS;

		if (this.maxWebSocketConnections < 0)
			throw "HttpServerOptions: maxWebSocketConnections must be >= 0";
		if (this.httpWorkerHeadroom < 1)
			throw "HttpServerOptions: httpWorkerHeadroom must be >= 1 (otherwise WebSockets can starve HTTP)";

		var minimum = minimumSafeWorkerPoolSize(this.maxWebSocketConnections, this.httpWorkerHeadroom);

		// Default the pool to exactly the safe minimum rather than to HxWell's
		// unsafe 10.
		this.workerPoolSize = init.workerPoolSize != null ? init.workerPoolSize : minimum;

		// Task K: refuse to construct an exhaustible server.
		if (this.workerPoolSize < minimum) {
			throw 'HttpServerOptions: workerPoolSize=${this.workerPoolSize} is unsafe. '
				+ 'Each WebSocket connection occupies one worker for its entire lifetime, so a pool '
				+ 'smaller than maxWebSocketConnections(${this.maxWebSocketConnections}) + '
				+ 'httpWorkerHeadroom(${this.httpWorkerHeadroom}) = ${minimum} can deadlock: at '
				+ '${this.workerPoolSize} concurrent WebSocket clients the server stops answering HTTP '
				+ 'and stops accepting new connections. Raise workerPoolSize to at least ${minimum}, '
				+ 'or lower maxWebSocketConnections.';
		}
	}

	/** Convenience for servers that do not accept WebSocket connections at all. */
	public static function httpOnly(host:String, port:Int, httpWorkers:Int = 16):HttpServerOptions {
		return new HttpServerOptions(host, port, {
			maxWebSocketConnections: 0,
			httpWorkerHeadroom: httpWorkers,
			workerPoolSize: httpWorkers
		});
	}
}

/**
 * Optional overrides for `HttpServerOptions`. Every field is nullable so an
 * omitted field takes the documented default rather than 0.
 */
typedef HttpServerOptionsInit = {
	var ?maxHeaderSize:Int;
	var ?maxUrlLength:Int;
	var ?maxRequestBodySize:Int;
	var ?maxWebSocketMessageSize:Int;
	var ?workerPoolSize:Int;
	var ?maxWebSocketConnections:Int;
	var ?httpWorkerHeadroom:Int;
	var ?maxConnections:Int;
}
