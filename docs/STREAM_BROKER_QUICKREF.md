# Stream Broker Quick Reference

## Quick Start

```haxe
// Get broker from DI
var broker = DI.get(IStreamBroker);

// Add messages
broker.xadd("tasks", {task: "send_email", userId: 123});

// Create consumer group
broker.createGroup("tasks", "workers", "0");

// Read and process
var messages = broker.xreadgroup("workers", "worker-1", "tasks", 10);
for (msg in messages) {
    processTask(msg.data);
    broker.xack("tasks", "workers", [msg.id]);
}
```

## HTTP API Examples

### Add Message
```bash
curl -X POST http://localhost:8000/stream/tasks/add \
  -H "Content-Type: application/json" \
  -d '{"task": "send_email", "userId": 123}'
```

### Create Consumer Group
```bash
curl -X POST http://localhost:8000/stream/tasks/group/workers \
  -H "Content-Type: application/json" \
  -d '{"startId": "0"}'
```

### Read Messages (Non-blocking)
```bash
curl "http://localhost:8000/stream/tasks/group/workers/consumer/worker-1?count=10&block=0"
```

### Read Messages (Blocking 5 seconds)
```bash
curl "http://localhost:8000/stream/tasks/group/workers/consumer/worker-1?count=10&block=5000"
```

### Acknowledge Messages
```bash
curl -X POST http://localhost:8000/stream/tasks/group/workers/ack \
  -H "Content-Type: application/json" \
  -d '{"messageIds": ["1738454400000-0", "1738454400000-1"]}'
```

### Get Stream Info
```bash
curl "http://localhost:8000/stream/tasks/info"
```

## Common Operations

| Operation | Method | Description |
|-----------|--------|-------------|
| `xadd` | Add message to stream | Fire-and-forget message publishing |
| `createGroup` | Create consumer group | Set up message processing group |
| `xreadgroup` | Read as consumer | Get messages (distributes load) |
| `xack` | Acknowledge | Confirm message processed |
| `xpending` | Check pending | See unacknowledged messages |
| `xautoclaim` | Claim stale | Recover from failed consumers |
| `xlen` | Get length | Count messages in stream |
| `xtrim` | Trim stream | Limit stream size |

## Message Flow

```
Producer                    Stream                  Consumer Group
   |                          |                           |
   | xadd(data)              |                           |
   |------------------------>|                           |
   |                          |                           |
   |                          | xreadgroup(group, c1)    |
   |                          |<--------------------------|
   |                          |  [message]                |
   |                          |-------------------------->|
   |                          |                           | (process)
   |                          |                           |
   |                          | xack(messageId)          |
   |                          |<--------------------------|
```

## DI Setup

```haxe
// Use local implementation (no Redis required)
DI.init(c -> {
    c.addSingleton(IStreamBroker, LocalStreamBroker);
});

// Later: Switch to Redis (same interface!)
DI.init(c -> {
    c.addSingleton(IStreamBroker, RedisStreamBroker);
});
```

## Worker Pattern

```haxe
// Worker loop
function startWorker(workerId:String):Void {
    var broker = DI.get(IStreamBroker);
    
    while (true) {
        // Block for 5 seconds waiting for work
        var messages = broker.xreadgroup(
            "job-processors",
            workerId,
            "jobs",
            1,
            5000
        );
        
        for (msg in messages) {
            try {
                // Process
                doWork(msg.data);
                
                // Acknowledge
                broker.xack("jobs", "job-processors", [msg.id]);
            } catch (e:Dynamic) {
                HybridLogger.error('Job failed: $e');
                // Don't ack - will be auto-claimed later
            }
        }
    }
}
```

## Key Differences from Polling

| Feature | PollingMessageBroker | StreamBroker |
|---------|---------------------|--------------|
| Persistence | In-memory only | Survives until trimmed |
| Consumer Groups | No | Yes |
| Load Distribution | No (broadcast only) | Yes |
| Acknowledgment | No | Yes |
| Fault Recovery | No | Yes (auto-claim) |
| Use Case | WebSocket replacement | Background jobs |

## When to Use

### Use StreamBroker for:
- Background job processing
- Task queues
- Event-driven workflows
- Reliable message delivery
- Load distribution across workers
- Fire-and-forget operations

### Use PollingMessageBroker for:
- Real-time bidirectional communication
- WebSocket replacement
- Client notifications
- Chat applications
- Live updates

## See Also
- [STREAM_BROKER_GUIDE.md](STREAM_BROKER_GUIDE.md) - Complete documentation
- [StreamBrokerDemo.hx](Source/sidewinder/StreamBrokerDemo.hx) - Working examples
