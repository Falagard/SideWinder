package sidewinder.native;

/**
 * HashLink native bindings for CivetWeb
 * Low-level interface to the CivetWeb C library
 */
@:hlNative("civetweb")
abstract CivetWebNative(hl.Abstract<"hl_civetweb_server">) {
	/**
	 * Create a new CivetWeb server instance
	 * @param host Host address (e.g., "127.0.0.1")
	 * @param port Port number
	 * @param documentRoot Optional document root for static files
	 * @return Server handle
	 */
	@:hlNative("civetweb", "create")
	public static function create(host:hl.Bytes, port:Int, documentRoot:hl.Bytes):CivetWebNative {
		return null;
	}

	/**
	 * Start the server (uses polling architecture - no callback)
	 * @param server Server handle
	 * @return True if started successfully
	 */
	@:hlNative("civetweb", "start")
	public static function start(server:CivetWebNative):Bool {
		return false;
	}

	/**
	 * Stop the server
	 * @param server Server handle
	 */
	@:hlNative("civetweb", "stop")
	public static function stop(server:CivetWebNative):Void {}

	/**
	 * Check if server is running
	 * @param server Server handle
	 * @return True if running
	 */
	@:hlNative("civetweb", "is_running")
	public static function isRunning(server:CivetWebNative):Bool {
		return false;
	}

	/**
	 * Get server port
	 * @param server Server handle
	 * @return Port number
	 */
	@:hlNative("civetweb", "get_port")
	public static function getPort(server:CivetWebNative):Int {
		return 0;
	}

	/**
	 * Get server host
	 * @param server Server handle
	 * @return Host address
	 */
	@:hlNative("civetweb", "get_host")
	public static function getHost(server:CivetWebNative):hl.Bytes {
		return null;
	}

	/**
	 * Free server resources
	 * @param server Server handle
	 */
	@:hlNative("civetweb", "free")
	public static function free(server:CivetWebNative):Void {}

	/**
	 * Set WebSocket connect handler
	 * @param handler Handler called when WebSocket connection is established
	 */
	@:hlNative("civetweb", "set_websocket_connect_handler")
	public static function setWebSocketConnectHandler(handler:Int->Void):Void {}

	/**
	 * Set WebSocket ready handler
	 * @param handler Handler called when WebSocket is ready to communicate
	 */
	@:hlNative("civetweb", "set_websocket_ready_handler")
	public static function setWebSocketReadyHandler(handler:Dynamic->Void):Void {}

	/**
	 * Set WebSocket data handler
	 * @param handler Handler called when WebSocket data is received
	 */
	@:hlNative("civetweb", "set_websocket_data_handler")
	public static function setWebSocketDataHandler(handler:Dynamic->Int->hl.Bytes->Int->Void):Void {}

	/**
	 * Set WebSocket close handler
	 * @param handler Handler called when WebSocket connection is closed
	 */
	@:hlNative("civetweb", "set_websocket_close_handler")
	public static function setWebSocketCloseHandler(handler:Dynamic->Void):Void {}

	/**
	 * Send data through WebSocket
	 * @param conn Connection handle
	 * @param opcode WebSocket opcode (1=text, 2=binary, 8=close, 9=ping, 10=pong)
	 * @param data Data to send
	 * @param length Length of data
	 * @return Bytes sent or -1 on error
	 */
	@:hlNative("civetweb", "websocket_send")
	public static function websocketSend(conn:Dynamic, opcode:Int, data:hl.Bytes, length:Int):Int {
		return -1;
	}

	/**
	 * Close WebSocket connection
	 * @param conn Connection handle
	 * @param code Close status code
	 * @param reason Close reason
	 */
	@:hlNative("civetweb", "websocket_close")
	public static function websocketClose(conn:Dynamic, code:Int, reason:hl.Bytes):Void {}

	// ============================================================================
	// POLLING ARCHITECTURE: New Functions
	// ============================================================================

	/**
	 * Poll for a single pending HTTP request (called from Haxe main thread)
	 * Returns request data object or null if queue is empty
	 * @param server Server handle
	 * @return Dynamic request object or null
	 */
	@:hlNative("civetweb", "poll_request")
	public static function pollRequest(server:CivetWebNative):Dynamic {
		return null;
	}

	/**
	 * Push a response for a request ID (called from Haxe main thread)
	 * @param server Server handle
	 * @param requestId Request ID from polled request
	 * @param statusCode HTTP status code
	 * @param contentType Content-Type header
	 * @param body Response body
	 * @param bodyLength Length of response body
	 */
	@:hlNative("civetweb", "push_response")
	public static function pushResponse(server:CivetWebNative, requestId:Int, statusCode:Int, contentType:hl.Bytes, body:hl.Bytes, bodyLength:Int):Void {}
}

/**
 * HTTP request data from CivetWeb
 */
typedef CivetWebRequest = {
	var uri:String;
	var method:String;
	var body:String;
	var bodyLength:Int;
	var queryString:String;
	var remoteAddr:String;
	var headers:String;
}

/**
 * HTTP response data for CivetWeb
 */
typedef CivetWebResponse = {
	var statusCode:Int;
	var contentType:String;
	var body:String;
	var bodyLength:Int;
}

/**
 * Queued request with ID (for polling architecture)
 */
typedef QueuedRequest = {
	var id:Int;
	var uri:String;
	var method:String;
	var body:String;
	var bodyLength:Int;
	var queryString:String;
	var remoteAddr:String;
	var headers:String;
}

/**
 * WebSocket opcodes
 */
enum abstract WebSocketOpcode(Int) from Int to Int {
	var TEXT = 0x1;
	var BINARY = 0x2;
	var CLOSE = 0x8;
	var PING = 0x9;
	var PONG = 0xA;
}
