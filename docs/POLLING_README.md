# SideWinder Polling Solution

A WebSocket-like messaging system for SideWinder using long-polling, designed for easy migration to real WebSockets.

## Quick Start

### Server Setup

The polling endpoints are automatically available when you run the server:

```bash
lime test hl
```

Server runs on `http://127.0.0.1:8000` with these new endpoints:
- `POST /poll/subscribe` - Subscribe a client
- `GET /poll/:clientId` - Long-polling for messages
- `POST /poll/broadcast` - Broadcast to all clients
- `POST /poll/send/:clientId` - Send to specific client

### Client Usage

```haxe
import sidewinder.PollingClient;
import sidewinder.IMessageClient;

// Create client
var client:IMessageClient = new PollingClient("http://127.0.0.1:8000");

// Set up WebSocket-like event handlers
client.onConnect = () -> trace("Connected!");
client.onMessage = (msg) -> trace("Received: " + msg);
client.onError = (err) -> trace("Error: " + err);
client.onDisconnect = () -> trace("Disconnected");

// Connect (starts automatic polling)
client.connect();

// Later: disconnect
client.disconnect();
```

### Server-Side Broadcasting

```haxe
var messageBroker:IMessageBroker = DI.get(IMessageBroker);

// Broadcast to all clients
messageBroker.broadcast(Json.stringify({
    type: "notification",
    message: "Hello everyone!"
}));

// Send to specific client
messageBroker.sendToClient("client_id", Json.stringify({
    type: "private",
    data: "Just for you"
}));
```

## Key Features

✅ **WebSocket-like API** - Familiar event-driven interface  
✅ **Long-polling** - Efficient 30-second blocking requests  
✅ **Auto-reconnection** - Exponential backoff (2s → 30s)  
✅ **Thread-safe** - Mutex-protected message queues  
✅ **Auto-cleanup** - Removes inactive clients after 5 minutes  
✅ **Cross-platform** - Works on sys targets AND HTML5/JavaScript  
✅ **Easy migration** - Interface-based design for WebSocket upgrade  

## Architecture

- **Server**: `IMessageBroker` interface with `PollingMessageBroker` implementation
- **Client**: `IMessageClient` interface with `PollingClient` implementation
- **Transport**: HTTP long-polling with JSON messages
- **Threading**: Background polling thread per client

## Migration to WebSockets

When WebSocket support is added:

1. Create `WebSocketMessageBroker implements IMessageBroker`
2. Create `WebSocketClient implements IMessageClient`
3. Update DI registration:
   ```haxe
   DI.init(c -> {
       c.addSingleton(IMessageBroker, WebSocketMessageBroker); // Changed!
   });
   ```
4. Update client creation:
   ```haxe
   var client:IMessageClient = new WebSocketClient("ws://localhost:8000");
   ```

**No application code changes needed!**


## HTML5 Support

The `PollingClient` works on **both sys and HTML5 targets** using conditional compilation!

### Quick Start (HTML5)

1. Open `static/polling_demo.html` in your browser
2. Make sure the server is running (`lime test hl`)
3. Click "Connect" to start receiving messages

### Building for HTML5

```bash
haxe -cp Source -main YourApp -js output.js
```

See [`HTML5_GUIDE.md`](HTML5_GUIDE.md) for detailed instructions.

## Files

### Server-Side
- `sidewinder/IMessageBroker.hx` - Interface
- `sidewinder/PollingMessageBroker.hx` - Implementation
- `Main.hx` - Polling endpoints (lines 184-354)

### Client-Side
- `sidewinder/IMessageClient.hx` - Interface
- `sidewinder/PollingClient.hx` - Implementation
- `PollingClientDemo.hx` - Usage example

## Testing

```bash
# Terminal 1: Run server
lime test hl

# Terminal 2: Test with cURL
curl -X POST http://localhost:8000/poll/subscribe \
  -H "Content-Type: application/json" \
  -d '{"clientId": "test1"}'

curl http://localhost:8000/poll/test1

# Terminal 3: Send message
curl -X POST http://localhost:8000/poll/send/test1 \
  -H "Content-Type: application/json" \
  -d '{"message": "{\"type\":\"test\",\"data\":\"Hello!\"}"}'
```

## Performance

- **Polling interval**: 30 seconds
- **Max queue size**: 100 messages per client
- **Cleanup interval**: 5 minutes
- **Suitable for**: 10-100 concurrent clients

## Documentation

See `walkthrough.md` for detailed documentation including:
- Complete API reference
- Architecture diagrams
- Usage examples
- Migration guide
- Performance tuning
