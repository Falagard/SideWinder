package sidewinder.websocket;

import haxe.Exception;
import haxe.io.Bytes;
import sidewinder.routing.Router.Request;

// SIDEWINDER-CORE-HYGIENE-S1 (typed WebSocket application API).
//
// Target-invariant WebSocket lifecycle. Prefer this over implementing
// `sidewinder.interfaces.IWebSocketHandler` directly in new code.
//
// Why this exists: `IWebSocketHandler.onData` declares `hl.Bytes` on HashLink
// and `haxe.io.Bytes` on every other target, so every implementer has to carry
// the same `#if hl`. That divergence is exactly what let a real defect survive
// uncompiled in the HxWell adapter's cpp branch. Here, text is a String and
// binary is always `haxe.io.Bytes`, on every target.
//
// Wire it up with `WebSocketApplicationHandler`, which implements the legacy
// interface and forwards to this one. Existing `IWebSocketHandler`
// implementations keep working untouched.
interface IWebSocketApplication {
	/** Return false to reject the upgrade. */
	function onConnect(request:Request):Bool;

	function onOpen(connection:IWebSocketConnection):Void;
	function onText(connection:IWebSocketConnection, message:String):Void;
	function onBinary(connection:IWebSocketConnection, data:Bytes):Void;

	/**
	 * Called when the connection ends.
	 *
	 * MUST be idempotent: HxWell's `SocketWebSocketHandler` fires its close
	 * path twice on a clean close handshake (once from the close-frame case in
	 * its message loop, once after the loop returns).
	 */
	function onClose(connection:IWebSocketConnection):Void;

	function onError(connection:IWebSocketConnection, error:Exception):Void;
}
