package sidewinder.websocket;

import haxe.io.Bytes;

// SIDEWINDER-CORE-HYGIENE-S1 (typed WebSocket application API).
//
// A typed handle for one WebSocket client. Application code should depend on
// this rather than on the untyped `conn:Dynamic` that `IWebSocketHandler`
// passes around, or on HxWell's `WebSocketSession` directly.
//
// Deliberately transport-neutral: nothing here names HxWell, so a handler
// written against it can be unit-tested with a fake connection and no socket.
interface IWebSocketConnection {
	/** Stable per-connection id, unique for the life of the connection. */
	var id(get, never):String;

	function sendText(message:String):Void;
	function sendBinary(data:Bytes):Void;
	function close(code:Int = 1000, ?reason:String):Void;
}
