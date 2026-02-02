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
            
            try {
                var msgData = haxe.Json.parse(message);
                
                switch (msgData.type) {
                    case "chat":
                        // Broadcast chat message to all users
                        HybridLogger.info('[ChatRoom] ${connInfo.username}: ${msgData.message}');
                        
                        var chatMsg = {
                            type: "chat",
                            username: connInfo.username,
                            userId: connInfo.userId,
                            message: msgData.message,
                            timestamp: Date.now().getTime()
                        };
                        broadcastToAll(haxe.Json.stringify(chatMsg));
                        
                    case "setname":
                        // Allow user to change their name
                        var oldName = connInfo.username;
                        var newName = msgData.username;
                        
                        if (newName != null && newName.length > 0 && newName.length <= 20) {
                            connInfo.username = newName;
                            
                            var nameMsg = {
                                type: "namechange",
                                oldName: oldName,
                                newName: newName,
                                message: '$oldName is now known as $newName'
                            };
                            broadcastToAll(haxe.Json.stringify(nameMsg));
                            
                            HybridLogger.info('[ChatRoom] $oldName changed name to $newName');
                        }
                        
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
                HybridLogger.error('[ChatRoom] Failed to parse message: $e');
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
            if (c.conn == conn) return c;
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
}
