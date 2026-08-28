package sidewinder.routing;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.interfaces.IWebSocketServer;

import hx.well.websocket.WebSocketSession;

import sidewinder.logging.HybridLogger;
import sidewinder.interfaces.IWebSocketHandler;




import haxe.Json;

/**
 * WebSocket router that dispatches connections to different handlers
 * based on the first message sent by the client.
 * 
 * Client sends: {"handler": "echo"} or {"handler": "chat"} etc.
 * Router assigns connection to appropriate handler.
 * 
 * Supported handlers: "echo", "chat", "broadcast", "auth"
 */
class WebSocketRouter implements IWebSocketHandler {
	private var adapter:IWebSocketServer;

	// Available handlers by name
	private var handlers:Map<String, IWebSocketHandler>;

	// Store connections with their state - using class instances for proper reference semantics
	private var connections:Array<RouterConnection>;

	/**
	 * SIDEWINDER-CORE-HYGIENE-S1: this constructor used to register four bundled
	 * sample handlers (echo/chat/broadcast/auth) unconditionally, so every
	 * consumer link-time depended on a chat room and a demo auth handler.
	 *
	 * Those samples were also silently STALE -- their `onConnect()` had not been
	 * updated when the interface gained a `req` parameter, and nothing in the
	 * repository ever compiled them. They now live under `dev/` (outside the
	 * haxelib classPath) and are registered explicitly by the dev entry point.
	 *
	 * Register your own handlers with `registerHandler(name, handler)`.
	 */
	public function new(adapter:IWebSocketServer) {
		this.adapter = adapter;
		this.handlers = new Map();
		this.connections = [];

		HybridLogger.info('[WebSocketRouter] Initialized with no handlers; call registerHandler(name, handler)');
	}

	/**
	 * Register a named handler
	 */
	public function registerHandler(name:String, handler:IWebSocketHandler):Void {
		handlers.set(name, handler);
	}

	/**
	 * Find connection entry by comparing connection pointers
	 */
	private function findConnection(conn:Dynamic):Null<RouterConnection> {
		for (entry in connections) {
			if (conn == entry.conn) {
				return entry;
			}
		}
		return null;
	}

	/**
	 * Remove connection entry
	 */
	private function removeConnection(conn:Dynamic):Void {
		connections = connections.filter(entry -> {
			return conn != entry.conn;
		});
	}

	public function onConnect(req:sidewinder.routing.Router.Request):Bool {
		// SIDEWINDER-CORE-HYGIENE-S1: this was `onConnect()` -- stale since the
		// interface gained `req`, and never caught because nothing in the
		// repository compiled this file.
		HybridLogger.info('[WebSocketRouter] New connection');
		return true; // Accept all connections
	}

	public function onReady(conn:Dynamic):Void {
		// Add connection as pending
		connections.push(new RouterConnection(conn));

		HybridLogger.info('[WebSocketRouter] Connection ready - awaiting handler selection (total: ${connections.length})');

		// Send instructions to client
		var instructions = Json.stringify({
			type: "router_init",
			message: "Send {\"handler\": \"<name>\"} to select handler",
			available: [for (k in handlers.keys()) k]
		});
		adapter.websocketSendText(conn, instructions);
	}

#if hl
	public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
		var entry = findConnection(conn);
		if (entry == null) {
			HybridLogger.warn('[WebSocketRouter] Received data for unknown connection');
			return;
		}

		var opcode = flags & 0x0F;

		// Only handle text messages for routing
		if (opcode != WebSocketOpcode.TEXT) {
			// If already assigned, forward to handler
			if (entry.handler != null) {
				entry.handler.onData(conn, flags, data, length);
			}
			return;
		}

		var message = @:privateAccess String.fromUTF8(data);

		// Check if connection is pending (needs handler assignment)
		if (entry.pending) {
			HybridLogger.info('[WebSocketRouter] Pending connection received: $message');
			try {
				var json:Dynamic = Json.parse(message);
				var handlerName:String = json.handler;

				if (handlerName != null && handlers.exists(handlerName)) {
					// Assign handler - this modifies the actual object since RouterConnection is a class
					var handler = handlers.get(handlerName);
					entry.handler = handler;
					entry.pending = false;

					HybridLogger.info('[WebSocketRouter] Connection assigned to handler: $handlerName');

					// Notify handler that connection is ready
					handler.onReady(conn);
				} else {
					// Unknown handler
					var availableHandlers = [for (k in handlers.keys()) k];
					adapter.websocketSendText(conn, Json.stringify({
						type: "error",
						message: "Unknown handler: " + handlerName,
						available: availableHandlers
					}));
				}
			} catch (e:Dynamic) {
				// Not valid JSON or missing handler field
				HybridLogger.warn('[WebSocketRouter] Failed to parse handler selection: $e');
				adapter.websocketSendText(conn, Json.stringify({
					type: "error",
					message: "Invalid request. Send {\"handler\": \"<name>\"}",
					available: [for (k in handlers.keys()) k]
				}));
			}
			return;
		}

		// Connection is assigned - forward to handler
		if (entry.handler != null) {
			entry.handler.onData(conn, flags, data, length);
		} else {
			HybridLogger.warn('[WebSocketRouter] Connection has no handler assigned but not pending');
		}
	}
#else
	public function onData(conn:Dynamic, flags:Int, data:haxe.io.Bytes, length:Int):Void {}
#end

	public function onClose(conn:Dynamic):Void {
		var entry = findConnection(conn);

		if (entry != null) {
			// Forward close to assigned handler
			if (entry.handler != null) {
				entry.handler.onClose(conn);
			}
			removeConnection(conn);
		}

		HybridLogger.info('[WebSocketRouter] Connection closed (remaining: ${connections.length})');
	}
}

/**
 * Connection state - using a class for proper reference semantics
 * (typedef structs are copied by value, which causes bugs when updating)
 */
class RouterConnection {
	public var conn:Dynamic;
	public var handler:Null<IWebSocketHandler>;
	public var pending:Bool;

	public function new(conn:Dynamic) {
		this.conn = conn;
		this.handler = null;
		this.pending = true;
	}
}






