package sidewinder;

import sidewinder.IWebSocketHandler;
import sidewinder.CivetWebAdapter;

/**
 * Chat room WebSocket handler
 * Manages multiple clients in a chat room with broadcasting
 */
class ChatRoomWebSocketHandler implements IWebSocketHandler {
	private var adapter:CivetWebAdapter;
	private var connections:Array<ConnectionInfo>;
	private var nextUserId:Int;

	public function new(adapter:CivetWebAdapter) {
		this.adapter = adapter;
		this.connections = [];
		this.nextUserId = 1;
	}

	public function onConnect():Bool {
		HybridLogger.info('[ChatRoom] New connection request');
		return true;
	}

	public function onReady(conn:Dynamic):Void {
		var userId = nextUserId++;
		var username = "User" + userId;

		connections.push({
			conn: conn,
			userId: userId,
			username: username,
			connectedAt: Date.now().getTime()
		});

		HybridLogger.info('[ChatRoom] User connected: $username (${connections.length} users online)');

		// Send welcome message to new user
		var welcomeMsg = {
			type: "system",
			message: 'Welcome to the chat room! You are $username',
			userCount: connections.length
		};
		adapter.websocketSendText(conn, haxe.Json.stringify(welcomeMsg));

		// Broadcast join notification to all other users
		var joinMsg = {
			type: "join",
			username: username,
			message: '$username joined the chat',
			userCount: connections.length
		};
		broadcastToOthers(conn, haxe.Json.stringify(joinMsg));

		// Send user list to new user
		var userList = connections.map(c -> c.username);
		var userListMsg = {
			type: "userlist",
			users: userList
		};
		adapter.websocketSendText(conn, haxe.Json.stringify(userListMsg));
	}

	public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
		var opcode = flags & 0x0F;

		if (opcode == WebSocketOpcode.TEXT) {
			var message = @:privateAccess String.fromUTF8(data);
			var connInfo = findConnection(conn);

			if (connInfo == null) {
				HybridLogger.warn('[ChatRoom] Message from unknown connection');
				return;
			}

			HybridLogger.info('[ChatRoom] Received from ${connInfo.username}: $message');

			// Handle plain text commands (for chatroom_demo.html compatibility)
			if (StringTools.startsWith(message, "/")) {
				handleCommand(conn, connInfo, message);
				return;
			}

			// Try to parse as JSON first
			try {
				var msgData = haxe.Json.parse(message);

				switch (msgData.type) {
					case "chat":
						// Broadcast chat message to all users
						broadcastChat(connInfo, msgData.message);

					case "setname":
						// Allow user to change their name
						changeNickname(conn, connInfo, msgData.username);

					case "ping":
						// Respond to ping
						var pongMsg = {
							type: "pong",
							timestamp: Date.now().getTime()
						};
						adapter.websocketSendText(conn, haxe.Json.stringify(pongMsg));

					default:
						HybridLogger.warn('[ChatRoom] Unknown message type: ${msgData.type}');
				}
			} catch (e:Dynamic) {
				// Not JSON - treat as plain chat message
				broadcastChat(connInfo, message);
			}
		}
	}

	private function handleCommand(conn:Dynamic, connInfo:ConnectionInfo, message:String):Void {
		var parts = message.split(" ");
		var command = parts[0].toLowerCase();
		var arg = parts.length > 1 ? parts.slice(1).join(" ") : "";

		switch (command) {
			case "/nick":
				if (arg.length > 0) {
					changeNickname(conn, connInfo, arg);
				} else {
					sendSystemMessage(conn, "Usage: /nick <name>");
				}

			case "/join":
				if (arg.length > 0) {
					connInfo.room = arg;
					sendSystemMessage(conn, 'Joined room: $arg');
					HybridLogger.info('[ChatRoom] ${connInfo.username} joined room: $arg');

					// Notify others in the room
					var joinMsg = {
						type: "join",
						username: connInfo.username,
						message: '${connInfo.username} joined the chat',
						userCount: getConnectionsInRoom(arg).length
					};
					broadcastToRoom(arg, haxe.Json.stringify(joinMsg));
				} else {
					sendSystemMessage(conn, "Usage: /join <room>");
				}

			case "/leave":
				if (connInfo.room != null) {
					var oldRoom = connInfo.room;
					connInfo.room = null;
					sendSystemMessage(conn, 'Left room: $oldRoom');

					var leaveMsg = {
						type: "leave",
						username: connInfo.username,
						message: '${connInfo.username} left the chat',
						userCount: getConnectionsInRoom(oldRoom).length
					};
					broadcastToRoom(oldRoom, haxe.Json.stringify(leaveMsg));
				}

			case "/rooms":
				var rooms = getRoomList();
				sendSystemMessage(conn, 'Active rooms: ${rooms.join(", ")}');

			case "/users":
				if (connInfo.room != null) {
					var users = getConnectionsInRoom(connInfo.room).map(c -> c.username);
					sendSystemMessage(conn, 'Users in ${connInfo.room}: ${users.join(", ")}');
				} else {
					sendSystemMessage(conn, "You're not in a room. Use /join <room> first.");
				}

			default:
				sendSystemMessage(conn, 'Unknown command: $command');
		}
	}

	private function changeNickname(conn:Dynamic, connInfo:ConnectionInfo, newName:String):Void {
		if (newName.length > 0 && newName.length <= 20) {
			var oldName = connInfo.username;
			connInfo.username = newName;

			var nameMsg = {
				type: "system",
				message: '$oldName is now known as $newName'
			};

			if (connInfo.room != null) {
				broadcastToRoom(connInfo.room, haxe.Json.stringify(nameMsg));
			} else {
				adapter.websocketSendText(conn, haxe.Json.stringify(nameMsg));
			}

			HybridLogger.info('[ChatRoom] $oldName changed name to $newName');
		}
	}

	private function broadcastChat(connInfo:ConnectionInfo, message:String):Void {
		HybridLogger.info('[ChatRoom] ${connInfo.username}: $message');

		var chatMsg = {
			type: "message",
			nickname: connInfo.username,
			userId: connInfo.userId,
			message: message,
			timestamp: Date.now().getTime()
		};

		if (connInfo.room != null) {
			// Broadcast to room only
			broadcastToRoom(connInfo.room, haxe.Json.stringify(chatMsg));
		} else {
			// Broadcast to all (legacy behavior)
			broadcastToAll(haxe.Json.stringify(chatMsg));
		}
	}

	private function sendSystemMessage(conn:Dynamic, message:String):Void {
		adapter.websocketSendText(conn, haxe.Json.stringify({
			type: "system",
			message: message
		}));
	}

	private function getConnectionsInRoom(room:String):Array<ConnectionInfo> {
		return connections.filter(c -> c.room == room);
	}

	private function getRoomList():Array<String> {
		var rooms:Map<String, Bool> = new Map();
		for (c in connections) {
			if (c.room != null) {
				rooms.set(c.room, true);
			}
		}
		return [for (k in rooms.keys()) k];
	}

	private function broadcastToRoom(room:String, message:String):Void {
		for (connInfo in connections) {
			if (connInfo.room == room) {
				adapter.websocketSendText(connInfo.conn, message);
			}
		}
	}

	public function onClose(conn:Dynamic):Void {
		var connInfo = findConnection(conn);

		if (connInfo != null) {
			connections.remove(connInfo);

			HybridLogger.info('[ChatRoom] User disconnected: ${connInfo.username} (${connections.length} users remaining)');

			// Broadcast leave notification
			var leaveMsg = {
				type: "leave",
				username: connInfo.username,
				message: '${connInfo.username} left the chat',
				userCount: connections.length
			};
			broadcastToAll(haxe.Json.stringify(leaveMsg));
		}
	}

	private function findConnection(conn:Dynamic):ConnectionInfo {
		for (c in connections) {
			if (c.conn == conn)
				return c;
		}
		return null;
	}

	private function broadcastToAll(message:String):Void {
		for (connInfo in connections) {
			adapter.websocketSendText(connInfo.conn, message);
		}
	}

	private function broadcastToOthers(excludeConn:Dynamic, message:String):Void {
		for (connInfo in connections) {
			if (connInfo.conn != excludeConn) {
				adapter.websocketSendText(connInfo.conn, message);
			}
		}
	}

	public function getConnectionCount():Int {
		return connections.length;
	}

	public function getUserList():Array<String> {
		return connections.map(c -> c.username);
	}
}

typedef ConnectionInfo = {
	var conn:Dynamic;
	var userId:Int;
	var username:String;
	var connectedAt:Float;
	@:optional var room:String;
}
