# SideWinder Messaging Systems Comparison

SideWinder includes three distinct messaging systems, each designed for different use cases:

## 1. StreamBroker (Fire-and-Forget Job Processing)

### When to Use
- Background job processing
- Task queues with workers
- Event-driven workflows
- Asynchronous operations that don't need immediate response
- Fire-and-forget messages
- Load distribution across multiple workers
- Reliable message delivery with acknowledgment

### Key Features
- ✅ Consumer groups for load distribution
- ✅ Message acknowledgment (XACK)
- ✅ Fault recovery via auto-claim
- ✅ Persistent (until trimmed)
- ✅ Blocking reads (long polling)
- ✅ Message history/replay
- ✅ Designed for Redis migration

### Example Use Cases
```
- Email sending queue
- Report generation
- Image processing
- Data import/export
- Scheduled tasks
- Webhook delivery
- Log processing
```

### API Style
```haxe
// Producer
broker.xadd("jobs", {task: "send_email", to: "user@example.com"});

// Consumer
var messages = broker.xreadgroup("workers", "worker-1", "jobs", 10);
for (msg in messages) {
    processJob(msg.data);
    broker.xack("jobs", "workers", [msg.id]);
}
```

---

## 2. PollingMessageBroker (WebSocket Alternative)

### When to Use
- Real-time bidirectional communication
- WebSocket replacement for client-server messaging
- Client notifications and updates
- Chat applications
- Live dashboards
- Server-to-client push updates

### Key Features
- ✅ Subscribe/unsubscribe pattern
- ✅ Broadcast to all clients
- ✅ Send to specific client
- ✅ Long polling support
- ✅ Temporary message queues
- ✅ Client activity tracking
- ❌ No acknowledgment
- ❌ No persistence
- ❌ No consumer groups

### Example Use Cases
```
- Chat rooms
- Live notifications
- Real-time status updates
- Server events to browser
- Online presence indicators
- Live collaboration tools
```

### API Style
```haxe
// Server side
broker.subscribe("client-123");
broker.sendToClient("client-123", jsonMessage);
broker.broadcast(jsonMessage);

// Client side (HTTP long polling)
POST /poll/subscribe {"clientId": "client-123"}
GET /poll/client-123  // Blocks until messages
```

---

## 3. WebSocket Handlers (True WebSockets)

### When to Use
- Low-latency bidirectional communication
- High-frequency updates (gaming, trading)
- Persistent connections
- Binary data transfer
- Real-time collaboration
- When you need actual WebSocket protocol

### Key Features
- ✅ True WebSocket protocol (RFC 6455)
- ✅ Full-duplex communication
- ✅ Low latency
- ✅ Binary and text frames
- ✅ Multiple handler implementations
- ✅ Authentication support
- ✅ Room/channel support

### Example Use Cases
```
- Real-time gaming
- Video/audio chat
- Live trading platforms
- Collaborative editing
- IoT device communication
- Screen sharing
```

### Available Handlers
```
- EchoWebSocketHandler: Echo server for testing
- ChatRoomWebSocketHandler: Multi-room chat
- BroadcastWebSocketHandler: Channel broadcasting
- AuthenticatedWebSocketHandler: Token-based auth
```

---

## Comparison Matrix

| Feature | StreamBroker | PollingMessageBroker | WebSocket |
|---------|--------------|---------------------|-----------|
| **Connection Type** | Stateless HTTP | Stateful HTTP | Persistent WS |
| **Communication** | Producer → Consumer | Bidirectional | Bidirectional |
| **Load Distribution** | ✅ Consumer groups | ❌ Broadcast only | ❌ Per connection |
| **Acknowledgment** | ✅ Required | ❌ None | Manual |
| **Persistence** | ✅ Until trimmed | ❌ Temporary | ❌ None |
| **Message History** | ✅ Yes | ❌ No | ❌ No |
| **Fault Recovery** | ✅ Auto-claim | ❌ None | Reconnect |
| **Latency** | Medium | Medium | Low |
| **Scalability** | High (workers) | Medium | Medium |
| **Client Complexity** | HTTP API | HTTP API | WebSocket API |
| **Server Resources** | Low | Medium | High |

---

## Decision Tree

```
Need real-time bidirectional communication?
├─ Yes → Need very low latency?
│  ├─ Yes → Use WebSocket
│  └─ No → Use PollingMessageBroker
└─ No → Need background processing?
   ├─ Yes → Need load distribution?
   │  ├─ Yes → Use StreamBroker
   │  └─ No → Could use StreamBroker anyway
   └─ No → Use direct HTTP request/response
```

---

## Architecture Patterns

### Pattern 1: Web App with Background Jobs

```
Browser ←→ HTTP API (Main.hx)
              ↓ (xadd)
          StreamBroker
              ↓ (xreadgroup)
          Background Workers
```

**Example:**
- User uploads CSV → API responds immediately
- StreamBroker queues processing job
- Worker processes CSV, sends email when done

---

### Pattern 2: Real-Time Dashboard

```
Browser ←→ PollingMessageBroker ←→ Server Events
     (long polling)              (broadcast updates)
```

**Example:**
- Multiple users viewing dashboard
- Server broadcasts updates every few seconds
- Clients poll /poll/:clientId for updates

---

### Pattern 3: Real-Time Collaboration

```
Browser A ←→ WebSocket Handler ←→ Browser B
          (room: "document-123")
```

**Example:**
- Multiple users editing document
- Low-latency cursor movements
- Instant text sync

---

### Pattern 4: Hybrid Architecture

```
                    ┌─── WebSocket ───→ Real-time chat
Client ←─ HTTP API ─┤
                    ├─── StreamBroker ─→ Email jobs
                    └─── Polling ──────→ Notifications
```

**Example:**
- Chat uses WebSocket for low latency
- Email sending uses StreamBroker for reliability
- Notifications use Polling for compatibility

---

## Migration Paths

### From PollingMessageBroker to WebSocket
```haxe
// 1. Enable WebSocket in CivetWebAdapter
var wsHandler = new ChatRoomWebSocketHandler(civetAdapter);
civetAdapter.setWebSocketHandler(wsHandler);

// 2. Update client code from HTTP polling to WebSocket
const ws = new WebSocket('ws://localhost:8000/ws');
```

### From LocalStreamBroker to Redis
```haxe
// 1. Implement RedisStreamBroker
// 2. Update DI configuration
DI.init(c -> {
    c.addSingleton(IStreamBroker, RedisStreamBroker);
});
// Application code unchanged!
```

---

## Performance Characteristics

### StreamBroker
- **Throughput**: High (thousands of messages/sec)
- **Latency**: Medium (HTTP request per batch)
- **Memory**: O(stream size × number of streams)
- **CPU**: Low (mostly I/O bound)

### PollingMessageBroker
- **Throughput**: Medium (limited by poll rate)
- **Latency**: Medium (poll interval dependent)
- **Memory**: O(queue size × number of clients)
- **CPU**: Medium (frequent polling)

### WebSocket
- **Throughput**: Very high (persistent connection)
- **Latency**: Very low (<10ms typical)
- **Memory**: O(number of connections)
- **CPU**: Low (event-driven)

---

## Best Practices

### StreamBroker
```haxe
✅ Always acknowledge messages after processing
✅ Use consumer groups for load distribution
✅ Set up periodic auto-claim for fault recovery
✅ Monitor pending message counts
✅ Trim streams to prevent unbounded growth
❌ Don't use for real-time client communication
❌ Don't forget to create consumer groups
```

### PollingMessageBroker
```haxe
✅ Use for browser compatibility (no WebSocket)
✅ Keep messages small (< 1KB)
✅ Set reasonable poll timeouts (30-60 seconds)
✅ Implement reconnection logic
❌ Don't use for high-frequency updates
❌ Don't rely on message delivery guarantees
```

### WebSocket
```haxe
✅ Implement ping/pong for connection health
✅ Handle reconnection on client side
✅ Use rooms/channels for organization
✅ Validate all incoming messages
❌ Don't send large payloads
❌ Don't forget authentication
```

---

## Examples by Scenario

### Scenario: E-commerce Platform

```haxe
// Order placement (HTTP)
App.post("/orders", (req, res) -> {
    var order = createOrder(req.jsonBody);
    
    // Fire-and-forget: Process payment
    streamBroker.xadd("payment-processing", {
        orderId: order.id,
        amount: order.total
    });
    
    // Fire-and-forget: Send confirmation email
    streamBroker.xadd("email-queue", {
        to: order.customerEmail,
        template: "order-confirmation",
        data: order
    });
    
    // Real-time: Notify admin dashboard
    pollingBroker.broadcast(Json.stringify({
        type: "new-order",
        order: order
    }));
    
    res.json({success: true, orderId: order.id});
});
```

### Scenario: Live Chat with Notifications

```haxe
// Real-time chat messages (WebSocket)
wsHandler.onMessage = (conn, msg) -> {
    wsHandler.broadcastToRoom(msg.roomId, msg.content);
};

// Background: Save message to database
streamBroker.xadd("chat-persistence", {
    roomId: msg.roomId,
    userId: msg.userId,
    content: msg.content
});

// Push notification for offline users
streamBroker.xadd("push-notifications", {
    userIds: offlineUserIds,
    message: msg.preview
});
```

---

## Testing

Each system includes test utilities:

```bash
# Test StreamBroker
curl -X POST http://localhost:8000/stream/test/add \
  -d '{"data": "test"}'

# Test PollingMessageBroker
curl -X POST http://localhost:8000/poll/subscribe \
  -d '{"clientId": "test-client"}'

# Test WebSocket
# Open static/websocket_test.html
```

---

## Summary

Choose the right tool for the job:

- **StreamBroker** = Background jobs, task queues, reliable delivery
- **PollingMessageBroker** = Real-time updates, browser compatibility
- **WebSocket** = Low latency, high frequency, true bidirectional

All three can coexist in the same application, each serving their specific purpose!
