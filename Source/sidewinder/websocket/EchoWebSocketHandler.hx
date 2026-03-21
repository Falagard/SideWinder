package sidewinder.websocket;
import sidewinder.interfaces.IWebSocketHandler.WebSocketCloseCode;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.interfaces.IWebSocketServer;

import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;





/**
 * Simple WebSocket echo handler for testing
 * Echoes back any received message
 */
class EchoWebSocketHandler implements IWebSocketHandler {
    private var adapter:IWebSocketServer;
    
    public function new(adapter:IWebSocketServer) {
        this.adapter = adapter;
    }
    
    public function onConnect():Bool {
        HybridLogger.info('[EchoWebSocket] New connection request');
        return true; // Accept all connections
    }
    
    public function onReady(conn:Dynamic):Void {
        HybridLogger.info('[EchoWebSocket] Connection ready');
        adapter.websocketSendText(conn, "Welcome to SideWinder WebSocket Echo Server!");
    }
    
#if hl
    public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
        // Extract opcode from flags (lower 4 bits)
        var opcode = flags & 0x0F;
        
        HybridLogger.info('[EchoWebSocket] Received data (opcode=$opcode, length=$length)');
        
        switch(opcode) {
            case WebSocketOpcode.TEXT:
                // Echo text message back
                var message = @:privateAccess String.fromUTF8(data);
                HybridLogger.info('[EchoWebSocket] Text message: $message');
                adapter.websocketSendText(conn, "Echo: " + message);
                
            case WebSocketOpcode.BINARY:
                // Echo binary data back
                HybridLogger.info('[EchoWebSocket] Binary data received');
                adapter.websocketSendBinary(conn, haxe.io.Bytes.ofData(cast data));
                
            case WebSocketOpcode.CLOSE:
                HybridLogger.info('[EchoWebSocket] Close frame received');
                adapter.websocketClose(conn, WebSocketCloseCode.NORMAL, "Server closing");
                
            case WebSocketOpcode.PING:
                HybridLogger.info('[EchoWebSocket] Ping received, sending pong');
                // CivetWeb handles ping/pong automatically
                
            default:
                HybridLogger.info('[EchoWebSocket] Unknown opcode: $opcode');
        }
    }
#else
    public function onData(conn:Dynamic, flags:Int, data:haxe.io.Bytes, length:Int):Void {}
#end
    
    public function onClose(conn:Dynamic):Void {
        HybridLogger.info('[EchoWebSocket] Connection closed');
    }
}




