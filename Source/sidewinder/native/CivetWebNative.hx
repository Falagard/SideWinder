package sidewinder.native;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;

/**
 * HashLink native bindings for CivetWeb
 * Low-level interface to the CivetWeb C library
 */
#if hl
@:hlNative("civetweb")
abstract CivetWebNative(hl.Abstract<"hl_civetweb_server">) {
	@:hlNative("civetweb", "create")
	public static function create(host:hl.Bytes, port:Int, documentRoot:hl.Bytes):CivetWebNative {
		return null;
	}

	@:hlNative("civetweb", "start")
	public static function start(server:CivetWebNative):Bool {
		return false;
	}

	@:hlNative("civetweb", "stop")
	public static function stop(server:CivetWebNative):Void {}

	@:hlNative("civetweb", "is_running")
	public static function isRunning(server:CivetWebNative):Bool {
		return false;
	}

	@:hlNative("civetweb", "get_port")
	public static function getPort(server:CivetWebNative):Int {
		return 0;
	}

	@:hlNative("civetweb", "get_host")
	public static function getHost(server:CivetWebNative):hl.Bytes {
		return null;
	}

	@:hlNative("civetweb", "free")
	public static function free(server:CivetWebNative):Void {}

	@:hlNative("civetweb", "poll_websocket_event")
	public static function pollWebSocketEvent(server:CivetWebNative):Dynamic {
		return null;
	}

	@:hlNative("civetweb", "websocket_send")
	public static function websocketSend(conn:hl.Bytes, opcode:Int, data:hl.Bytes, length:Int):Int {
		return -1;
	}

	@:hlNative("civetweb", "websocket_close")
	public static function websocketClose(conn:hl.Bytes, code:Int, reason:hl.Bytes):Void {}

	@:hlNative("civetweb", "poll_request")
	public static function pollRequest(server:CivetWebNative):Dynamic {
		return null;
	}

	@:hlNative("civetweb", "push_response")
	public static function pushResponse(server:CivetWebNative, requestId:Int, statusCode:Int, contentType:hl.Bytes, body:hl.Bytes, bodyLength:Int):Void {}
}
#else
abstract CivetWebNative(Dynamic) {
	public static function create(host:Dynamic, port:Int, documentRoot:Dynamic):CivetWebNative return null;
	public static function start(server:CivetWebNative):Bool return false;
	public static function stop(server:CivetWebNative):Void {}
	public static function isRunning(server:CivetWebNative):Bool return false;
	public static function getPort(server:CivetWebNative):Int return 0;
	public static function getHost(server:CivetWebNative):Dynamic return null;
	public static function free(server:CivetWebNative):Void {}
	public static function pollWebSocketEvent(server:CivetWebNative):Dynamic return null;
	public static function websocketSend(conn:Dynamic, opcode:Int, data:Dynamic, length:Int):Int return -1;
	public static function websocketClose(conn:Dynamic, code:Int, reason:Dynamic):Void {}
	public static function pollRequest(server:CivetWebNative):Dynamic return null;
	public static function pushResponse(server:CivetWebNative, requestId:Int, statusCode:Int, contentType:Dynamic, body:Dynamic, bodyLength:Int):Void {}
}
#end

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


