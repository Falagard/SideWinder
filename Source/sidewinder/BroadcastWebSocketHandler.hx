package sidewinder;

import sidewinder.IWebSocketHandler;
import sidewinder.CivetWebAdapter;

/**
 * Broadcasting WebSocket handler
 * Manages channels/rooms with subscription-based broadcasting
 */
class BroadcastWebSocketHandler implements IWebSocketHandler {
    private var adapter:CivetWebAdapter;
    private var connections:Map<Dynamic, ClientConnection>;
    private var channels:Map<String, Array<Dynamic>>;
    
    public function new(adapter:CivetWebAdapter) {
        this.adapter = adapter;
        this.connections = new Map();
        this.channels = new Map();
    }
    
    public function onConnect():Bool {
        HybridLogger.info('[Broadcast] New connection request');
        return true;
    }
    
    public function onReady(conn:Dynamic):Void {
        connections.set(conn, {
            conn: conn,
            channels: [],
            connectedAt: Date.now().getTime()
        });
        
        HybridLogger.info('[Broadcast] Client connected (${Lambda.count(connections)} total)');
        
        var welcomeMsg = {
            type: "connected",
            message: "Connected to broadcast server",
            availableChannels: getChannelList()
        };
        adapter.websocketSendText(conn, haxe.Json.stringify(welcomeMsg));
    }
    
    public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
        var opcode = flags & 0x0F;
        
        if (opcode == WebSocketOpcode.TEXT) {
            var message = @:privateAccess String.fromUTF8(data);
            var client = connections.get(conn);
            
            if (client == null) {
                HybridLogger.warn('[Broadcast] Message from unknown connection');
                return;
            }
            
            try {
                var msgData = haxe.Json.parse(message);
                
                switch (msgData.type) {
                    case "subscribe":
                        // Subscribe to a channel
                        var channelName = msgData.channel;
                        if (channelName != null) {
                            subscribeToChannel(conn, channelName);
                        }
                        
                    case "unsubscribe":
                        // Unsubscribe from a channel
                        var channelName = msgData.channel;
                        if (channelName != null) {
                            unsubscribeFromChannel(conn, channelName);
                        }
                        
                    case "publish":
                        // Publish message to a channel
                        var channelName = msgData.channel;
                        var content = msgData.message;
                        if (channelName != null && content != null) {
                            publishToChannel(channelName, content, conn);
                        }
                        
                    case "create":
                        // Create a new channel
                        var channelName = msgData.channel;
                        if (channelName != null) {
                            createChannel(channelName, conn);
                        }
                        
                    case "list":
                        // List available channels
                        var channelList = getChannelInfo();
                        var listMsg = {
                            type: "channels",
                            channels: channelList
                        };
                        adapter.websocketSendText(conn, haxe.Json.stringify(listMsg));
                        
                    default:
                        HybridLogger.warn('[Broadcast] Unknown message type: ${msgData.type}');
                }
            } catch (e:Dynamic) {
                HybridLogger.error('[Broadcast] Failed to parse message: $e');
            }
        }
    }
    
    public function onClose(conn:Dynamic):Void {
        var client = connections.get(conn);
        
        if (client != null) {
            // Unsubscribe from all channels
            for (channelName in client.channels) {
                unsubscribeFromChannel(conn, channelName, true);
            }
            
            connections.remove(conn);
            HybridLogger.info('[Broadcast] Client disconnected (${Lambda.count(connections)} remaining)');
        }
    }
    
    private function createChannel(channelName:String, creator:Dynamic):Void {
        if (channels.exists(channelName)) {
            var errorMsg = {
                type: "error",
                message: 'Channel "$channelName" already exists'
            };
            adapter.websocketSendText(creator, haxe.Json.stringify(errorMsg));
            return;
        }
        
        channels.set(channelName, []);
        HybridLogger.info('[Broadcast] Channel created: $channelName');
        
        var successMsg = {
            type: "created",
            channel: channelName,
            message: 'Channel "$channelName" created successfully'
        };
        adapter.websocketSendText(creator, haxe.Json.stringify(successMsg));
    }
    
    private function subscribeToChannel(conn:Dynamic, channelName:String):Void {
        var client = connections.get(conn);
        if (client == null) return;
        
        // Create channel if it doesn't exist
        if (!channels.exists(channelName)) {
            channels.set(channelName, []);
        }
        
        var subscribers = channels.get(channelName);
        
        // Check if already subscribed
        if (subscribers.indexOf(conn) != -1) {
            var alreadyMsg = {
                type: "error",
                message: 'Already subscribed to "$channelName"'
            };
            adapter.websocketSendText(conn, haxe.Json.stringify(alreadyMsg));
            return;
        }
        
        subscribers.push(conn);
        client.channels.push(channelName);
        
        HybridLogger.info('[Broadcast] Client subscribed to: $channelName (${subscribers.length} subscribers)');
        
        var subMsg = {
            type: "subscribed",
            channel: channelName,
            message: 'Subscribed to "$channelName"',
            subscriberCount: subscribers.length
        };
        adapter.websocketSendText(conn, haxe.Json.stringify(subMsg));
    }
    
    private function unsubscribeFromChannel(conn:Dynamic, channelName:String, silent:Bool = false):Void {
        var client = connections.get(conn);
        if (client == null) return;
        
        if (!channels.exists(channelName)) return;
        
        var subscribers = channels.get(channelName);
        subscribers.remove(conn);
        client.channels.remove(channelName);
        
        HybridLogger.info('[Broadcast] Client unsubscribed from: $channelName (${subscribers.length} subscribers)');
        
        if (!silent) {
            var unsubMsg = {
                type: "unsubscribed",
                channel: channelName,
                message: 'Unsubscribed from "$channelName"'
            };
            adapter.websocketSendText(conn, haxe.Json.stringify(unsubMsg));
        }
        
        // Clean up empty channels
        if (subscribers.length == 0) {
            channels.remove(channelName);
            HybridLogger.info('[Broadcast] Channel removed (no subscribers): $channelName');
        }
    }
    
    private function publishToChannel(channelName:String, content:String, publisher:Dynamic):Void {
        if (!channels.exists(channelName)) {
            var errorMsg = {
                type: "error",
                message: 'Channel "$channelName" does not exist'
            };
            adapter.websocketSendText(publisher, haxe.Json.stringify(errorMsg));
            return;
        }
        
        var subscribers = channels.get(channelName);
        
        var broadcastMsg = {
            type: "message",
            channel: channelName,
            message: content,
            timestamp: Date.now().getTime()
        };
        
        var msgJson = haxe.Json.stringify(broadcastMsg);
        var deliveredCount = 0;
        
        for (conn in subscribers) {
            adapter.websocketSendText(conn, msgJson);
            deliveredCount++;
        }
        
        HybridLogger.info('[Broadcast] Message published to $channelName: $deliveredCount subscribers');
        
        // Confirm to publisher
        var confirmMsg = {
            type: "published",
            channel: channelName,
            subscriberCount: deliveredCount
        };
        adapter.websocketSendText(publisher, haxe.Json.stringify(confirmMsg));
    }
    
    private function getChannelList():Array<String> {
        var list = [];
        for (name in channels.keys()) {
            list.push(name);
        }
        return list;
    }
    
    private function getChannelInfo():Array<ChannelInfo> {
        var info = [];
        for (name in channels.keys()) {
            var subscribers = channels.get(name);
            info.push({
                name: name,
                subscriberCount: subscribers.length
            });
        }
        return info;
    }
    
    public function getChannelCount():Int {
        return Lambda.count(channels);
    }
    
    public function getConnectionCount():Int {
        return Lambda.count(connections);
    }
}

typedef ClientConnection = {
    var conn:Dynamic;
    var channels:Array<String>;
    var connectedAt:Float;
}

typedef ChannelInfo = {
    var name:String;
    var subscriberCount:Int;
}
