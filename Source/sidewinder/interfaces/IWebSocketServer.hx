package sidewinder.interfaces;
import sidewinder.interfaces.IWebSocketServer;

import haxe.io.Bytes;

/**
 * Interface for web servers that support WebSockets.
 * Allows handlers to send data back to the client without being tied to a specific adapter.
 */
interface IWebSocketServer {
	function websocketSendText(conn:Dynamic, text:String):Void;
	function websocketSendBinary(conn:Dynamic, data:Bytes):Void;
	function websocketClose(conn:Dynamic, code:Int = 1000, ?reason:String):Void;
}

