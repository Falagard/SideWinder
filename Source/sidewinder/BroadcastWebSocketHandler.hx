package sidewinder;

import sidewinder.IWebSocketHandler;
import sidewinder.CivetWebAdapter;

/**
 * Broadcasting WebSocket handler
 * Simple broadcast to all connected clients
 */
class BroadcastWebSocketHandler implements IWebSocketHandler {
	private var adapter:CivetWebAdapter;
	private var connections:Array<BroadcastConnection>;
	private var nextClientId:Int;
	private var totalMessages:Int;
	private var startTime:Float;

	public function new(adapter:CivetWebAdapter) {
		this.adapter = adapter;
		this.connections = [];
		this.nextClientId = 1;
		this.totalMessages = 0;
		this.startTime = Date.now().getTime();
	}

	public function onConnect():Bool {
		HybridLogger.info('[Broadcast] New connection request');
		return true;
	}

	public function onReady(conn:Dynamic):Void {
		var clientId = "client-" + nextClientId++;
		var client = new BroadcastConnection(conn, clientId);
		connections.push(client);

		HybridLogger.info('[Broadcast] Client connected: $clientId (${connections.length} total)');

		// Send welcome message with expected format for broadcast_demo.html
		var welcomeMsg = {
			type: "welcome",
			message: "Connected to broadcast server",
			clientId: clientId,
			totalClients: connections.length
		};
		adapter.websocketSendText(conn, haxe.Json.stringify(welcomeMsg));
	}

	public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
		var opcode = flags & 0x0F;

		if (opcode == WebSocketOpcode.TEXT) {
			var message = @:privateAccess String.fromUTF8(data);
			var client = findConnection(conn);

			if (client == null) {
				HybridLogger.warn('[Broadcast] Message from unknown connection');
				return;
			}

			HybridLogger.info('[Broadcast] Received from ${client.clientId}: $message');

			try {
				var msgData = haxe.Json.parse(message);

				switch (msgData.type) {
					case "broadcast":
						// Broadcast message to all clients
						var content:String = msgData.message;
						if (content != null) {
							totalMessages++;
							client.messageCount++;

							var broadcastMsg = {
								type: "broadcast",
								from: client.clientId,
								message: content,
								messageId: totalMessages,
								timestamp: Date.now().getTime()
							};
							broadcastToAll(haxe.Json.stringify(broadcastMsg));
						}

					case "stats":
						// Return stats for this client
						var statsMsg = {
							type: "stats",
							totalClients: connections.length,
							totalMessages: totalMessages,
							yourMessages: client.messageCount,
							uptime: Date.now().getTime() - startTime
						};
						adapter.websocketSendText(conn, haxe.Json.stringify(statsMsg));

					case "ping":
						var pongMsg = {
							type: "pong",
							timestamp: Date.now().getTime()
						};
						adapter.websocketSendText(conn, haxe.Json.stringify(pongMsg));

					default:
						HybridLogger.warn('[Broadcast] Unknown message type: ${msgData.type}');
				}
			} catch (e:Dynamic) {
				// Plain text - broadcast as is
				totalMessages++;
				client.messageCount++;

				var broadcastMsg = {
					type: "broadcast",
					from: client.clientId,
					message: message,
					messageId: totalMessages,
					timestamp: Date.now().getTime()
				};
				broadcastToAll(haxe.Json.stringify(broadcastMsg));
			}
		}
	}

	public function onClose(conn:Dynamic):Void {
		var client = findConnection(conn);

		if (client != null) {
			connections.remove(client);
			HybridLogger.info('[Broadcast] Client disconnected: ${client.clientId} (${connections.length} remaining)');

			// Notify remaining clients
			var leaveMsg = {
				type: "system",
				message: '${client.clientId} disconnected',
				totalClients: connections.length
			};
			broadcastToAll(haxe.Json.stringify(leaveMsg));
		}
	}

	private function findConnection(conn:Dynamic):Null<BroadcastConnection> {
		var connBytes:hl.Bytes = conn;
		for (client in connections) {
			var clientBytes:hl.Bytes = client.conn;
			if (connBytes == clientBytes) {
				return client;
			}
		}
		return null;
	}

	private function broadcastToAll(message:String):Void {
		for (client in connections) {
			adapter.websocketSendText(client.conn, message);
		}
	}

	public function getConnectionCount():Int {
		return connections.length;
	}
}

/**
 * Connection state - using a class for proper reference semantics
 */
class BroadcastConnection {
	public var conn:Dynamic;
	public var clientId:String;
	public var messageCount:Int;
	public var connectedAt:Float;

	public function new(conn:Dynamic, clientId:String) {
		this.conn = conn;
		this.clientId = clientId;
		this.messageCount = 0;
		this.connectedAt = Date.now().getTime();
	}
}
