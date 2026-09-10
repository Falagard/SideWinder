package sidewinder.http;

// SIDEWINDER-CORE-DECOUPLING-S1 (Task D).
//
// Transport-level configuration for a SideWinder HTTP/WebSocket server.
//
// This interface exists so the HxWell transport adapter can be configured
// WITHOUT depending on any host application's configuration type. Before this
// existed, `CustomSocketDriver` did `DI.get(core.IServerConfig)` on every
// request -- which meant (a) the transport could not be used without the
// HaxeStackPlatform Server application on the classpath, and (b) DI was
// mandatory just to host an HTTP endpoint.
//
// Everything here is genuinely transport-level. Application configuration
// (database paths, node ids, cloud credentials, auth) must NOT be added to
// this interface -- put it on the host application's own config type and
// attach it per-request via `HxWellAdapter.onScopeSetup`.
interface IHttpServerOptions {
	/** Bind address, e.g. "127.0.0.1" or "0.0.0.0". */
	var host(default, null):String;

	/** Listening port. */
	var port(default, null):Int;

	/** Maximum total size in bytes of a request's header block. */
	var maxHeaderSize(default, null):Int;

	/** Maximum length in bytes of a request URL. */
	var maxUrlLength(default, null):Int;

	/** Maximum accepted `Content-Length` in bytes. */
	var maxRequestBodySize(default, null):Int;

	/** Maximum accepted inbound WebSocket message size in bytes. */
	var maxWebSocketMessageSize(default, null):Int;

	/**
	 * Size of the worker pool that serves both HTTP requests and WebSocket
	 * connections.
	 *
	 * CRITICAL: a WebSocket connection occupies one worker for its ENTIRE
	 * lifetime (`SocketWebSocketHandler.upgrade()` blocks until close). The
	 * pool must therefore be sized as:
	 *
	 *     workerPoolSize >= maxWebSocketConnections + httpWorkerHeadroom
	 *
	 * `HttpServerOptions` enforces this invariant; see its docs and
	 * `WebSocketAdmissionPolicy`.
	 */
	var workerPoolSize(default, null):Int;

	/**
	 * Hard ceiling on concurrently-accepted WebSocket connections. Upgrades
	 * beyond this are refused with 503 rather than being allowed to consume
	 * the worker pool's HTTP headroom.
	 */
	var maxWebSocketConnections(default, null):Int;

	/**
	 * Workers that must remain available to HTTP after `maxWebSocketConnections`
	 * WebSockets are established.
	 */
	var httpWorkerHeadroom(default, null):Int;

	/** Listen backlog passed to the underlying socket. */
	var maxConnections(default, null):Int;
}
