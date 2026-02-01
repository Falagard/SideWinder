package sidewinder;

import sidewinder.IWebSocketHandler;
import sidewinder.CivetWebAdapter;

/**
 * Authenticated WebSocket handler
 * Requires authentication token before allowing communication
 */
class AuthenticatedWebSocketHandler implements IWebSocketHandler {
    private var adapter:CivetWebAdapter;
    private var connections:Map<Dynamic, AuthenticatedClient>;
    private var validTokens:Map<String, TokenInfo>;
    private var authTimeout:Float; // seconds
    
    public function new(adapter:CivetWebAdapter, authTimeout:Float = 10.0) {
        this.adapter = adapter;
        this.connections = new Map();
        this.validTokens = new Map();
        this.authTimeout = authTimeout;
        
        // Generate some demo tokens
        generateDemoTokens();
    }
    
    private function generateDemoTokens():Void {
        // In production, these would come from a database or auth service
        validTokens.set("demo-token-123", {
            token: "demo-token-123",
            userId: 1,
            username: "demo-user",
            expiresAt: Date.now().getTime() + 3600000 // 1 hour
        });
        
        validTokens.set("admin-token-456", {
            token: "admin-token-456",
            userId: 2,
            username: "admin",
            expiresAt: Date.now().getTime() + 3600000
        });
    }
    
    public function onConnect():Bool {
        HybridLogger.info('[Auth] New connection request');
        return true; // Accept connection, but require auth
    }
    
    public function onReady(conn:Dynamic):Void {
        connections.set(conn, {
            conn: conn,
            authenticated: false,
            authToken: null,
            userId: null,
            username: null,
            connectedAt: Date.now().getTime(),
            authDeadline: Date.now().getTime() + (authTimeout * 1000)
        });
        
        HybridLogger.info('[Auth] Connection ready, awaiting authentication...');
        
        var authMsg = {
            type: "auth_required",
            message: "Please authenticate within " + authTimeout + " seconds",
            timeout: authTimeout
        };
        adapter.websocketSendText(conn, haxe.Json.stringify(authMsg));
    }
    
    public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
        var opcode = flags & 0x0F;
        
        if (opcode == WebSocketOpcode.TEXT) {
            var message = @:privateAccess String.fromUTF8(data);
            var client = connections.get(conn);
            
            if (client == null) {
                HybridLogger.warn('[Auth] Message from unknown connection');
                return;
            }
            
            try {
                var msgData = haxe.Json.parse(message);
                
                // Check if authenticated
                if (!client.authenticated) {
                    // Only allow auth messages
                    if (msgData.type == "auth") {
                        handleAuthentication(conn, client, msgData.token);
                    } else {
                        var errorMsg = {
                            type: "error",
                            message: "Authentication required"
                        };
                        adapter.websocketSendText(conn, haxe.Json.stringify(errorMsg));
                    }
                    return;
                }
                
                // Handle authenticated messages
                switch (msgData.type) {
                    case "ping":
                        var pongMsg = {
                            type: "pong",
                            timestamp: Date.now().getTime()
                        };
                        adapter.websocketSendText(conn, haxe.Json.stringify(pongMsg));
                        
                    case "echo":
                        var echoMsg = {
                            type: "echo",
                            message: msgData.message,
                            username: client.username
                        };
                        adapter.websocketSendText(conn, haxe.Json.stringify(echoMsg));
                        
                    case "broadcast":
                        // Broadcast to all authenticated users
                        var broadcastMsg = {
                            type: "broadcast",
                            from: client.username,
                            message: msgData.message,
                            timestamp: Date.now().getTime()
                        };
                        broadcastToAuthenticated(haxe.Json.stringify(broadcastMsg));
                        
                    case "whisper":
                        // Send private message to specific user
                        var targetUser = msgData.target;
                        var whisperMsg = {
                            type: "whisper",
                            from: client.username,
                            message: msgData.message,
                            timestamp: Date.now().getTime()
                        };
                        sendToUser(targetUser, haxe.Json.stringify(whisperMsg));
                        
                    case "userlist":
                        // Get list of authenticated users
                        var users = getAuthenticatedUsers();
                        var listMsg = {
                            type: "userlist",
                            users: users
                        };
                        adapter.websocketSendText(conn, haxe.Json.stringify(listMsg));
                        
                    default:
                        HybridLogger.warn('[Auth] Unknown message type: ${msgData.type}');
                }
            } catch (e:Dynamic) {
                HybridLogger.error('[Auth] Failed to parse message: $e');
            }
        }
    }
    
    public function onClose(conn:Dynamic):Void {
        var client = connections.get(conn);
        
        if (client != null) {
            if (client.authenticated) {
                HybridLogger.info('[Auth] Authenticated user disconnected: ${client.username}');
                
                // Notify other users
                var leaveMsg = {
                    type: "user_left",
                    username: client.username,
                    timestamp: Date.now().getTime()
                };
                broadcastToAuthenticated(haxe.Json.stringify(leaveMsg));
            } else {
                HybridLogger.info('[Auth] Unauthenticated connection closed');
            }
            
            connections.remove(conn);
        }
    }
    
    private function handleAuthentication(conn:Dynamic, client:AuthenticatedClient, token:String):Void {
        // Check auth deadline
        if (Date.now().getTime() > client.authDeadline) {
            var timeoutMsg = {
                type: "auth_timeout",
                message: "Authentication timeout"
            };
            adapter.websocketSendText(conn, haxe.Json.stringify(timeoutMsg));
            adapter.websocketClose(conn, WebSocketCloseCode.POLICY_VIOLATION, "Authentication timeout");
            return;
        }
        
        // Validate token
        var tokenInfo = validTokens.get(token);
        
        if (tokenInfo == null) {
            var failMsg = {
                type: "auth_failed",
                message: "Invalid token"
            };
            adapter.websocketSendText(conn, haxe.Json.stringify(failMsg));
            HybridLogger.warn('[Auth] Authentication failed: Invalid token');
            return;
        }
        
        // Check token expiration
        if (Date.now().getTime() > tokenInfo.expiresAt) {
            var expiredMsg = {
                type: "auth_failed",
                message: "Token expired"
            };
            adapter.websocketSendText(conn, haxe.Json.stringify(expiredMsg));
            HybridLogger.warn('[Auth] Authentication failed: Token expired');
            return;
        }
        
        // Authentication successful
        client.authenticated = true;
        client.authToken = token;
        client.userId = tokenInfo.userId;
        client.username = tokenInfo.username;
        
        HybridLogger.info('[Auth] User authenticated: ${client.username} (userId=${client.userId})');
        
        var successMsg = {
            type: "auth_success",
            message: "Authentication successful",
            userId: client.userId,
            username: client.username
        };
        adapter.websocketSendText(conn, haxe.Json.stringify(successMsg));
        
        // Notify other authenticated users
        var joinMsg = {
            type: "user_joined",
            username: client.username,
            timestamp: Date.now().getTime()
        };
        broadcastToAuthenticatedExcept(conn, haxe.Json.stringify(joinMsg));
    }
    
    private function broadcastToAuthenticated(message:String):Void {
        for (client in connections) {
            if (client.authenticated) {
                adapter.websocketSendText(client.conn, message);
            }
        }
    }
    
    private function broadcastToAuthenticatedExcept(excludeConn:Dynamic, message:String):Void {
        for (client in connections) {
            if (client.authenticated && client.conn != excludeConn) {
                adapter.websocketSendText(client.conn, message);
            }
        }
    }
    
    private function sendToUser(username:String, message:String):Void {
        for (client in connections) {
            if (client.authenticated && client.username == username) {
                adapter.websocketSendText(client.conn, message);
                return;
            }
        }
    }
    
    private function getAuthenticatedUsers():Array<UserInfo> {
        var users = [];
        for (client in connections) {
            if (client.authenticated) {
                users.push({
                    userId: client.userId,
                    username: client.username
                });
            }
        }
        return users;
    }
    
    public function addToken(token:String, userId:Int, username:String, expiresIn:Float = 3600000):Void {
        validTokens.set(token, {
            token: token,
            userId: userId,
            username: username,
            expiresAt: Date.now().getTime() + expiresIn
        });
        HybridLogger.info('[Auth] Token added: $username (expires in ${expiresIn/1000}s)');
    }
    
    public function revokeToken(token:String):Void {
        validTokens.remove(token);
        HybridLogger.info('[Auth] Token revoked: $token');
    }
    
    public function getAuthenticatedCount():Int {
        var count = 0;
        for (client in connections) {
            if (client.authenticated) count++;
        }
        return count;
    }
}

typedef AuthenticatedClient = {
    var conn:Dynamic;
    var authenticated:Bool;
    var authToken:String;
    var userId:Int;
    var username:String;
    var connectedAt:Float;
    var authDeadline:Float;
}

typedef TokenInfo = {
    var token:String;
    var userId:Int;
    var username:String;
    var expiresAt:Float;
}

typedef UserInfo = {
    var userId:Int;
    var username:String;
}
