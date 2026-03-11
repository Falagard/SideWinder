# WebSocket Support in SideWinder

## Overview
SideWinder supports WebSocket connections through the CivetWeb adapter, enabling real-time bidirectional communication. Multiple handler implementations are provided for different use cases.

## Quick Start

### 1. Select a WebSocket Handler

Edit `Source/Main.hx` and change the `wsHandlerType` variable:

```haxe
var wsHandlerType = "chat"; // Options: "echo", "chat", "broadcast", "auth"
```

### 2. Build and Run

```bash
# Build native library
./build_civetweb.sh

# Run server
lime test hl
```

### 3. Test in Browser

- **Echo**: `http://localhost:8000/websocket_test.html`
- **Chat Room**: `http://localhost:8000/chatroom_demo.html`
- **Broadcast**: `http://localhost:8000/broadcast_demo.html`
- **Authenticated**: `http://localhost:8000/auth_demo.html`

## WebSocket Handler Examples

### Echo Handler
Simple echo server that reflects messages back to the sender.

**Use Case**: Testing, debugging, simple request-response patterns

**Features**:
- Echoes text messages with "Echo: " prefix
- Handles binary data
- Sends welcome message on connect

**Test Page**: `websocket_test.html`

### Chat Room Handler
Multi-user chat room with user management and broadcasting.

**Use Case**: Chat applications, collaborative tools, live discussions

**Features**:
- Automatic user naming (User1, User2, etc.)
- Join/leave notifications
- User list updates
- Broadcast messages to all users
- Private messaging support
- User count tracking

**Test Page**: `chatroom_demo.html`

**Message Format**:
```json
// Send message
{"type": "message", "message": "Hello everyone!"}

// Private message
{"type": "private", "to": "User2", "message": "Secret message"}

// Change username
{"type": "setname", "username": "CoolUser"}
```

### Broadcast Handler
Channel-based pub/sub messaging system.

**Use Case**: News feeds, notifications, multi-topic communication

**Features**:
- Subscribe to multiple channels
- Publish to specific channels
- Create channels dynamically
- List available channels
- Message history per channel

**Test Page**: `broadcast_demo.html`

**Message Format**:
```json
// Subscribe to channel
{"type": "subscribe", "channel": "news"}

// Publish to channel
{"type": "publish", "channel": "news", "message": "Breaking news!"}

// Unsubscribe
{"type": "unsubscribe", "channel": "news"}

// List channels
{"type": "list"}
```

### Authenticated Handler
Token-based authentication for secure connections.

**Use Case**: Secure applications, user-specific data, access control

**Features**:
- Token-based authentication
- Authentication timeout (configurable)
- Session management
- User identification
- Secure message routing

**Test Page**: `auth_demo.html`

**Demo Tokens**:
- `demo-token-123` (user: demo-user, id: 1)
- `admin-token-456` (user: admin, id: 2)

**Message Format**:
```json
// Authenticate (must be first message)
{"type": "auth", "token": "demo-token-123"}

// Send message (after authenticated)
{"type": "message", "message": "Hello!"}
```

## Architecture

### Native Layer (C)
- **File**: `native/civetweb/civetweb_hl.c`
- **Components**:
  - WebSocket callback handlers (connect, ready, data, close)
  - Native functions for sending/closing WebSocket connections
  - Integration with CivetWeb's WebSocket API

### Haxe Bindings
- **File**: `Source/sidewinder/native/CivetWebNative.hx`
- **Functions**:
  - `setWebSocketConnectHandler` - Register connection handler
  - `setWebSocketReadyHandler` - Register ready handler
  - `setWebSocketDataHandler` - Register data handler
  - `setWebSocketCloseHandler` - Register close handler
  - `websocketSend` - Send data through WebSocket
  - `websocketClose` - Close WebSocket connection

### Adapter Layer
- **File**: `Source/sidewinder/CivetWebAdapter.hx`
- **Methods**:
  - `setWebSocketHandler(handler:IWebSocketHandler)` - Register WebSocket handler
  - `websocketSendText(conn, text)` - Send text message
  - `websocketSendBinary(conn, data)` - Send binary message
  - `websocketClose(conn, code, reason)` - Close connection

### Interface
- **File**: `Source/sidewinder/IWebSocketHandler.hx`
- **Methods**:
  - `onConnect()` - Called when connection established
  - `onReady(conn)` - Called when ready to communicate
  - `onData(conn, flags, data, length)` - Called when data received
  - `onClose(conn)` - Called when connection closed

## Constants

### WebSocket Opcodes
- `TEXT (0x1)` - Text frame
- `BINARY (0x2)` - Binary frame
- `CLOSE (0x8)` - Close frame
- `PING (0x9)` - Ping frame
- `PONG (0xA)` - Pong frame

### Close Status Codes
- `NORMAL (1000)` - Normal closure
- `GOING_AWAY (1001)` - Endpoint going away
- `PROTOCOL_ERROR (1002)` - Protocol error
- `UNSUPPORTED_DATA (1003)` - Unsupported data
- `INVALID_PAYLOAD (1007)` - Invalid payload
- `MESSAGE_TOO_BIG (1009)` - Message too big
- `INTERNAL_ERROR (1011)` - Internal error

## Example: Echo WebSocket Handler

```haxe
class EchoWebSocketHandler implements IWebSocketHandler {
    private var adapter:CivetWebAdapter;
    
    public function new(adapter:CivetWebAdapter) {
        this.adapter = adapter;
    }
    
    public function onConnect():Bool {
        HybridLogger.info('New WebSocket connection');
        return true; // Accept connection
    }
    
    public function onReady(conn:Dynamic):Void {
        adapter.websocketSendText(conn, "Welcome to SideWinder!");
    }
    
    public function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void {
        var opcode = flags & 0x0F;
        
        if (opcode == WebSocketOpcode.TEXT) {
            var message = @:privateAccess String.fromUTF8(data);
            adapter.websocketSendText(conn, "Echo: " + message);
        }
    }
    
    public function onClose(conn:Dynamic):Void {
        HybridLogger.info('WebSocket connection closed');
    }
}
```

## Usage in Main.hx

```haxe
// Create CivetWeb server
webServer = WebServerFactory.create(
    WebServerFactory.WebServerType.CivetWeb,
    DEFAULT_ADDRESS,
    DEFAULT_PORT,
    SideWinderRequestHandler,
    directory
);

// Setup WebSocket support
if (Std.isOfType(webServer, CivetWebAdapter)) {
    var civetAdapter:CivetWebAdapter = cast webServer;
    var wsHandler = new EchoWebSocketHandler(civetAdapter);
    civetAdapter.setWebSocketHandler(wsHandler);
}

webServer.start();
```

## Client-Side Testing

Use the provided test page:
```bash
# Start server
lime test hl

# Open browser to:
http://localhost:8000/websocket_test.html
```

The test page provides:
- Connection/disconnection controls
- Message sending interface
- Real-time message display (sent/received)
- Connection statistics (uptime, message counts)

## WebSocket URL Format

```
ws://host:port/ws
```

Example: `ws://localhost:8000/ws`

## Features

1. **Bidirectional Communication**: Full-duplex communication between client and server
2. **Text and Binary Messages**: Support for both text and binary data frames
3. **Connection Management**: Proper connection lifecycle handling
4. **Error Handling**: Robust error handling with close codes
5. **Ping/Pong**: Automatic keep-alive handling by CivetWeb

## Implementation Notes

1. **Thread Safety**: WebSocket callbacks are invoked from CivetWeb threads but bridge to Haxe main thread
2. **Connection Handles**: Connection objects are managed by CivetWeb and passed to handlers
3. **Opcode Handling**: The `flags` parameter contains WebSocket frame opcodes (lower 4 bits)
4. **Binary Safety**: Both text and binary data are supported with proper encoding

## Building

```bash
# Build native library
cd native/civetweb
make clean
make
make install

# Build and run project
lime test hl
```

## Testing

1. Start the server
2. Open `http://localhost:8000/websocket_test.html` in browser
3. Click "Connect" to establish WebSocket connection
4. Send messages and verify echo responses
5. Monitor connection status and statistics

## Future Enhancements

- [ ] WebSocket routing (multiple endpoints)
- [ ] WebSocket authentication
- [ ] Message broadcasting to multiple clients
- [ ] Room/channel support
- [ ] Compression support (permessage-deflate)
- [ ] SSL/TLS WebSocket support (wss://)
