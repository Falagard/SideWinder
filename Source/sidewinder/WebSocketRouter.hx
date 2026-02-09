package sidewinder;

import sidewinder.IWebSocketHandler;
import sidewinder.CivetWebAdapter;
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
	private var adapter:CivetWebAdapter;

	// Available handlers by name
	private var handlers:Map<String, IWebSocketHandler>;

	// Store connections with their state - using class instances for proper reference semantics
	private var connections:Array<RouterConnection>;

	public function new(adapter:CivetWebAdapter) {
		this.adapter = adapter;
		this.handlers = new Map();
		this.connections = [];

		// Register default handlers
		registerHandler("echo", new EchoWebSocketHandler(adapter));
		registerHandler("chat", new ChatRoomWebSocketHandler(adapter));
		registerHandler("broadcast", new BroadcastWebSocketHandler(adapter));
		registerHandler("auth", new AuthenticatedWebSocketHandler(adapter, 30.0));

		HybridLogger.info('[WebSocketRouter] Initialized with handlers: echo, chat, broadcast, auth');
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
		var connBytes:hl.Bytes = conn;
		for (entry in connections) {
			var entryBytes:hl.Bytes = entry.conn;
			if (connBytes == entryBytes) {
				return entry;
			}
		}
		return null;
	}

	/**
	 * Remove connection entry
	 */
	private function removeConnection(conn:Dynamic):Void {
		var connBytes:hl.Bytes = conn;
		connections = connections.filter(entry -> {
			var entryBytes:hl.Bytes = entry.conn;
			return connBytes != entryBytes;
		});
	}

	public function onConnect():Bool {
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
			available: ["echo", "chat", "broadcast", "auth"]
		});
		adapter.websocketSendText(conn, instructions);
	}

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
					available: ["echo", "chat", "broadcast", "auth"]
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
