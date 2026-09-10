package sidewinder.websocket;

import haxe.Exception;
import haxe.io.Bytes;
import sidewinder.interfaces.IWebSocketHandler;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.interfaces.IWebSocketServer;
import sidewinder.routing.Router.Request;

// SIDEWINDER-CORE-HYGIENE-S1 (typed WebSocket application API).
//
// Bridges the legacy `IWebSocketHandler` (untyped `conn:Dynamic`, raw opcodes,
// per-target `onData` signature) to the typed, target-invariant
// `IWebSocketApplication`.
//
// This is purely additive: register it with
// `adapter.setWebSocketHandler(new WebSocketApplicationHandler(adapter, myApp))`.
// Nothing about the adapter's dispatch changes, so existing
// `IWebSocketHandler` implementations -- including HaxeStackPlatform's
// `app.api.WebSocketHandler` and `RelayWebSocketHandler` -- are untouched.
//
// The `hl.Bytes` vs `haxe.io.Bytes` conversion happens HERE, once, instead of
// in every application handler.
class WebSocketApplicationHandler implements IWebSocketHandler {
	final server:IWebSocketServer;
	final app:IWebSocketApplication;
	final connections = new Map<String, BoundConnection>();
	final mutex = new sys.thread.Mutex();

	public function new(server:IWebSocketServer, app:IWebSocketApplication) {
		this.server = server;
		this.app = app;
	}

	public function onConnect(req:Request):Bool {
		return app.onConnect(req);
	}

	public function onReady(conn:Dynamic):Void {
		app.onOpen(bind(conn));
	}

#if hl
	public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
		// haxe.io.Bytes on HashLink wraps an hl.Bytes plus an explicit length;
		// the constructor is private, hence @:privateAccess.
		var bytes:Bytes = @:privateAccess new Bytes(data, length);
#else
	public function onData(conn:Dynamic, flags:Int, data:Bytes, length:Int):Void {
		var bytes:Bytes = (length == data.length) ? data : data.sub(0, length);
#end
		var connection = bind(conn);
		try {
			// `flags` carries the opcode; the adapter reports TEXT or BINARY.
			if (flags == WebSocketOpcode.BINARY) {
				app.onBinary(connection, bytes);
			} else {
				app.onText(connection, bytes.toString());
			}
		} catch (e:Exception) {
			app.onError(connection, e);
		}
	}

	public function onClose(conn:Dynamic):Void {
		var connection = bind(conn);
		// Unbind BEFORE dispatching so a re-entrant close cannot resurrect the
		// entry. The application's onClose must still be idempotent -- HxWell
		// calls this twice on a clean close handshake.
		mutex.acquire();
		connections.remove(connection.id);
		mutex.release();
		app.onClose(connection);
	}

	/** Wraps the adapter's untyped connection handle, one instance per client. */
	function bind(conn:Dynamic):IWebSocketConnection {
		var key = connectionId(conn);
		mutex.acquire();
		var bound = connections.get(key);
		if (bound == null) {
			bound = new BoundConnection(server, conn, key);
			connections.set(key, bound);
		}
		mutex.release();
		return bound;
	}

	static function connectionId(conn:Dynamic):String {
		// HxWell's WebSocketSession exposes `id`; fall back to object identity
		// for any other transport rather than throwing.
		var id:Dynamic = null;
		try {
			id = Reflect.field(conn, "id");
		} catch (e:Dynamic) {}
		return id != null ? Std.string(id) : Std.string(conn);
	}
}

/** `IWebSocketConnection` backed by an `IWebSocketServer` + its opaque handle. */
private class BoundConnection implements IWebSocketConnection {
	public var id(get, never):String;

	final server:IWebSocketServer;
	final conn:Dynamic;
	final _id:String;

	public function new(server:IWebSocketServer, conn:Dynamic, id:String) {
		this.server = server;
		this.conn = conn;
		this._id = id;
	}

	function get_id():String {
		return _id;
	}

	public function sendText(message:String):Void {
		server.websocketSendText(conn, message);
	}

	public function sendBinary(data:Bytes):Void {
		server.websocketSendBinary(conn, data);
	}

	public function close(code:Int = 1000, ?reason:String):Void {
		server.websocketClose(conn, code, reason);
	}
}
