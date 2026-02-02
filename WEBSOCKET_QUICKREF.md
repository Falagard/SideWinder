# WebSocket Quick Reference

## Switch Handler (Main.hx)

```haxe
var wsHandlerType = "chat"; // Change this line
```

| Type | Handler | Test URL | Use Case |
|------|---------|----------|----------|
| `"echo"` | EchoWebSocketHandler | /websocket_test.html | Testing, debugging |
| `"chat"` | ChatRoomWebSocketHandler | /chatroom_demo.html | Multi-user chat |
| `"broadcast"` | BroadcastWebSocketHandler | /broadcast_demo.html | Pub/sub channels |
| `"auth"` | AuthenticatedWebSocketHandler | /auth_demo.html | Secure connections |

## Message Formats

### Echo Handler
```javascript
// Just send any text
ws.send("Hello world!");
```

### Chat Room Handler
```javascript
// Send message to all
ws.send(JSON.stringify({type: "message", message: "Hello!"}));

// Private message
ws.send(JSON.stringify({type: "private", to: "User2", message: "Hi!"}));

// Change username
ws.send(JSON.stringify({type: "setname", username: "NewName"}));
```

### Broadcast Handler
```javascript
// Subscribe to channel
ws.send(JSON.stringify({type: "subscribe", channel: "news"}));

// Publish message
ws.send(JSON.stringify({type: "publish", channel: "news", message: "Update!"}));

// Unsubscribe
ws.send(JSON.stringify({type: "unsubscribe", channel: "news"}));

// List channels
ws.send(JSON.stringify({type: "list"}));
```

### Authenticated Handler
```javascript
// Authenticate first (required!)
ws.send(JSON.stringify({type: "auth", token: "demo-token-123"}));

// Then send messages
ws.send(JSON.stringify({type: "message", message: "Hello!"}));
```

**Demo Tokens**:
- `demo-token-123` (user)
- `admin-token-456` (admin)

## Creating Custom Handler

```haxe
class MyWebSocketHandler implements IWebSocketHandler {
    private var adapter:CivetWebAdapter;
    
    public function new(adapter:CivetWebAdapter) {
        this.adapter = adapter;
    }
    
    public function onConnect():Bool {
        return true; // Accept connection
    }
    
    public function onReady(conn:Dynamic):Void {
        adapter.websocketSendText(conn, "Welcome!");
    }
    
    public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
        var opcode = flags & 0x0F;
        if (opcode == WebSocketOpcode.TEXT) {
            var message = @:privateAccess String.fromUTF8(data);
            // Handle message
            adapter.websocketSendText(conn, "Got: " + message);
        }
    }
    
    public function onClose(conn:Dynamic):Void {
        // Cleanup
    }
}
```

## WebSocket Opcodes

| Opcode | Value | Description |
|--------|-------|-------------|
| TEXT | 0x1 | Text frame |
| BINARY | 0x2 | Binary frame |
| CLOSE | 0x8 | Close frame |
| PING | 0x9 | Ping frame |
| PONG | 0xA | Pong frame |

## Close Status Codes

| Code | Name | Description |
|------|------|-------------|
| 1000 | NORMAL | Normal closure |
| 1001 | GOING_AWAY | Endpoint going away |
| 1002 | PROTOCOL_ERROR | Protocol error |
| 1003 | UNSUPPORTED_DATA | Unsupported data |
| 1007 | INVALID_PAYLOAD | Invalid payload |
| 1009 | MESSAGE_TOO_BIG | Message too big |
| 1011 | INTERNAL_ERROR | Internal error |

## Common Tasks

### Send Text Message
```haxe
adapter.websocketSendText(conn, "Hello!");
```

### Send Binary Data
```haxe
adapter.websocketSendBinary(conn, bytes);
```

### Close Connection
```haxe
adapter.websocketClose(conn, WebSocketCloseCode.NORMAL, "Goodbye");
```

### Parse Message Opcode
```haxe
var opcode = flags & 0x0F;
switch (opcode) {
    case WebSocketOpcode.TEXT: // Handle text
    case WebSocketOpcode.BINARY: // Handle binary
    case WebSocketOpcode.CLOSE: // Handle close
}
```

## Client-Side JavaScript

```javascript
// Connect
const ws = new WebSocket('ws://localhost:8000/ws');

// Event handlers
ws.onopen = (event) => {
    console.log('Connected');
    ws.send('Hello server!');
};

ws.onmessage = (event) => {
    console.log('Received:', event.data);
};

ws.onerror = (error) => {
    console.error('Error:', error);
};

ws.onclose = (event) => {
    console.log('Closed:', event.code, event.reason);
};

// Send message
ws.send('Hello!');

// Close connection
ws.close(1000, 'Done');
```

## Build & Test

```bash
# Build native library
cd native/civetweb && make clean && make && make install

# Run server
lime test hl

# Open browser to test page
# http://localhost:8000/websocket_test.html
```

## Troubleshooting

**Connection refused**: Make sure CivetWeb server is running and using CivetWeb adapter in Main.hx

**Authentication timeout**: Increase timeout in Main.hx:
```haxe
var wsHandler = new AuthenticatedWebSocketHandler(civetAdapter, 60.0); // 60 seconds
```

**Messages not received**: Check if handler type matches the client test page

**Build errors**: Rebuild native library:
```bash
cd native/civetweb && make clean && make && make install
```
