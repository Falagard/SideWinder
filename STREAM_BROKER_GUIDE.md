# Stream Broker System

A fire-and-forget message handling system modeled after Redis Streams and Consumer Groups. This system provides reliable message processing with support for consumer groups, acknowledgments, and automatic message recovery.

## Overview

The Stream Broker system is designed for:
- **Fire-and-forget messaging**: Producers add messages without waiting for processing
- **Reliable delivery**: Messages are tracked until acknowledged
- **Load distribution**: Consumer groups distribute work across multiple consumers
- **Fault tolerance**: Auto-claim mechanism recovers messages from failed consumers
- **Easy migration**: Local implementation matches Redis Streams API for seamless future migration

## Key Concepts

### Stream
A named message queue (e.g., "notifications", "tasks", "events"). Messages are appended in order with unique IDs.

### Consumer Group
A logical group of consumers that process messages from a stream. Each message is delivered to only one consumer in the group, enabling load distribution.

### Consumer
An individual processor within a consumer group. Consumers read messages, process them, and acknowledge completion.

### Pending Messages
Messages delivered to a consumer but not yet acknowledged. Tracked per consumer for reliability.

### Auto-claim
Mechanism to reassign messages from inactive/failed consumers to active ones after a timeout.

## Implementations

### LocalStreamBroker
Thread-safe in-memory implementation for single-instance applications.
- No external dependencies
- Suitable for development and single-server deployments
- Automatic stream trimming to prevent memory bloat
- Full consumer group support with pending message tracking

### RedisStreamBroker (Coming Soon)
Distributed implementation using Redis Streams for multi-instance applications.
- Identical API to LocalStreamBroker
- Shared state across multiple servers
- Leverages Redis persistence and replication
- Production-ready for high-availability scenarios

## Usage Examples

### 1. Simple Fire-and-Forget

```haxe
var broker:IStreamBroker = DI.get(IStreamBroker);

// Producer: Add messages to stream
broker.xadd("notifications", {
    type: "email",
    to: "user@example.com",
    subject: "Welcome!"
});

broker.xadd("notifications", {
    type: "sms",
    to: "+1234567890",
    message: "Your code is 1234"
});
```

### 2. Consumer Group Processing

```haxe
var broker:IStreamBroker = DI.get(IStreamBroker);
var streamName = "tasks";
var groupName = "workers";

// Create consumer group (one time)
broker.createGroup(streamName, groupName, "0"); // Start from beginning

// Worker 1: Read and process messages
var messages = broker.xreadgroup(groupName, "worker-1", streamName, 10);
for (msg in messages) {
    // Process message
    processTask(msg.data);
    
    // Acknowledge completion
    broker.xack(streamName, groupName, [msg.id]);
}

// Worker 2: Automatically gets different messages
var messages2 = broker.xreadgroup(groupName, "worker-2", streamName, 10);
// ... process and ack ...
```

### 3. Blocking Reads (Long Polling)

```haxe
// Block for up to 5 seconds waiting for messages
var messages = broker.xreadgroup(
    "workers",
    "worker-1",
    "tasks",
    1,                    // count: read 1 message
    5000                  // blockMs: wait up to 5 seconds
);

if (messages.length > 0) {
    // Process message
    processTask(messages[0].data);
    broker.xack("tasks", "workers", [messages[0].id]);
}
```

### 4. Auto-Claim Stale Messages

```haxe
// Claim messages that have been pending for more than 30 seconds
var claimed = broker.xautoclaim(
    "tasks",              // stream
    "workers",            // group
    "worker-2",           // this consumer
    30000,                // minIdleMs: 30 seconds
    10                    // count: claim up to 10 messages
);

for (msg in claimed) {
    // Process recovered message
    processTask(msg.data);
    broker.xack("tasks", "workers", [msg.id]);
}
```

### 5. Monitoring and Management

```haxe
// Check stream length
var length = broker.xlen("tasks");
trace('Stream has $length messages');

// Get consumer group information
var groups = broker.getGroupInfo("tasks");
for (group in groups) {
    trace('Group: ${group.name}');
    trace('  Last ID: ${group.lastDeliveredId}');
    trace('  Pending: ${group.totalPending}');
    
    for (consumer in group.consumers) {
        trace('  Consumer: ${consumer.name}');
        trace('    Pending: ${consumer.pending}');
        trace('    Last activity: ${consumer.lastActivity}');
    }
}

// Check pending messages for a specific consumer
var pending = broker.xpending("tasks", "workers", "worker-1");
trace('Worker-1 has ${pending.length} pending messages');

// Trim stream to prevent unbounded growth
var removed = broker.xtrim("tasks", 1000); // Keep last 1000 messages
trace('Removed $removed old messages');
```

## API Reference

### Producer Operations

#### `xadd(stream:String, data:Dynamic):String`
Add a message to a stream. Returns auto-generated message ID.

**Example:**
```haxe
var msgId = broker.xadd("logs", {level: "error", message: "Database connection failed"});
```

### Consumer Group Management

#### `createGroup(stream:String, group:String, startId:String = "$"):Void`
Create a consumer group for a stream.
- `startId = "0"`: Process from beginning
- `startId = "$"`: Process only new messages (default)

**Example:**
```haxe
broker.createGroup("tasks", "workers", "0");
```

#### `deleteGroup(stream:String, group:String):Void`
Delete a consumer group and all its pending messages.

#### `deleteConsumer(stream:String, group:String, consumer:String):Int`
Remove a consumer from a group. Returns number of pending messages it had.

### Consumer Operations

#### `xreadgroup(group:String, consumer:String, stream:String, count:Int = 1, ?blockMs:Null<Int>):Array<StreamMessage>`
Read messages as a consumer in a group.
- `count`: Maximum messages to read
- `blockMs`: Blocking timeout (0 = no block, null = block forever)

**Example:**
```haxe
// Non-blocking
var messages = broker.xreadgroup("workers", "worker-1", "tasks", 10, 0);

// Block for 5 seconds
var messages = broker.xreadgroup("workers", "worker-1", "tasks", 10, 5000);
```

#### `xack(stream:String, group:String, messageIds:Array<String>):Int`
Acknowledge message processing. Returns number of messages acknowledged.

**Example:**
```haxe
broker.xack("tasks", "workers", [msg1.id, msg2.id, msg3.id]);
```

#### `xpending(stream:String, group:String, ?consumer:String):Array<StreamMessage>`
Get pending (unacknowledged) messages for a group or specific consumer.

#### `xautoclaim(stream:String, group:String, consumer:String, minIdleMs:Int, count:Int = 1):Array<StreamMessage>`
Claim pending messages from idle consumers. Used for fault recovery.

### Stream Management

#### `xlen(stream:String):Int`
Get the number of messages in a stream.

#### `xtrim(stream:String, maxLen:Int):Int`
Trim stream to maximum length. Returns number of messages removed.

#### `getGroupInfo(stream:String):Array<ConsumerGroupInfo>`
Get detailed information about all consumer groups for a stream.

## Dependency Injection Setup

Register the stream broker in your DI configuration:

```haxe
// In your App.hx or main initialization
DI.init(collection -> {
    // ... other services ...
    
    // Use local implementation
    collection.addSingleton(IStreamBroker, LocalStreamBroker);
    
    // Later, swap to Redis (same interface!)
    // collection.addSingleton(IStreamBroker, RedisStreamBroker);
});

// Then use anywhere in your app
var broker = DI.get(IStreamBroker);
```

## Common Patterns

### Background Job Processing

```haxe
// Producer (in API handler)
function scheduleJob(jobType:String, data:Dynamic):Void {
    var broker = DI.get(IStreamBroker);
    broker.xadd("background-jobs", {
        type: jobType,
        data: data,
        createdAt: Date.now().getTime()
    });
}

// Consumer (background worker)
function processJobs():Void {
    var broker = DI.get(IStreamBroker);
    broker.createGroup("background-jobs", "job-processors", "$");
    
    while (true) {
        var messages = broker.xreadgroup(
            "job-processors",
            "worker-${Sys.getEnv('WORKER_ID')}",
            "background-jobs",
            1,
            5000  // 5 second timeout
        );
        
        for (msg in messages) {
            try {
                executeJob(msg.data.type, msg.data.data);
                broker.xack("background-jobs", "job-processors", [msg.id]);
            } catch (e:Dynamic) {
                HybridLogger.error('Job failed: $e');
                // Don't ack - message will be auto-claimed later
            }
        }
    }
}
```

### Event Broadcasting

```haxe
// Publisher
function publishEvent(eventType:String, payload:Dynamic):Void {
    var broker = DI.get(IStreamBroker);
    broker.xadd("events", {
        type: eventType,
        payload: payload,
        timestamp: Date.now().getTime()
    });
}

// Multiple subscriber groups can process the same events
broker.createGroup("events", "analytics-processors", "$");
broker.createGroup("events", "notification-senders", "$");
broker.createGroup("events", "audit-loggers", "$");

// Each group processes independently
```

### Rate-Limited Processing

```haxe
function processWithRateLimit():Void {
    var broker = DI.get(IStreamBroker);
    var lastProcessTime = 0.0;
    var minInterval = 0.1; // 100ms between messages
    
    while (true) {
        var messages = broker.xreadgroup("workers", "rate-limited", "tasks", 1);
        
        if (messages.length > 0) {
            var now = Sys.time();
            var elapsed = now - lastProcessTime;
            
            if (elapsed < minInterval) {
                Sys.sleep(minInterval - elapsed);
            }
            
            processTask(messages[0].data);
            broker.xack("tasks", "workers", [messages[0].id]);
            lastProcessTime = Sys.time();
        } else {
            Sys.sleep(0.1);
        }
    }
}
```

## Best Practices

1. **Always acknowledge messages**: Don't forget to call `xack()` after successful processing
2. **Use auto-claim**: Set up periodic auto-claim to recover from consumer failures
3. **Monitor pending messages**: Check `xpending()` to detect stuck consumers
4. **Trim streams**: Use `xtrim()` to prevent unbounded growth
5. **Unique consumer names**: Use worker IDs or hostnames for consumer identification
6. **Error handling**: Don't ack messages that failed processing - let auto-claim handle retries
7. **Blocking reads**: Use blocking reads to reduce polling overhead
8. **Stream naming**: Use descriptive names (e.g., "user-notifications", "order-events")

## Migration to Redis

When ready to migrate from LocalStreamBroker to Redis:

1. Install Redis and the Haxe Redis library
2. Implement RedisStreamBroker with the same IStreamBroker interface
3. Update DI configuration to use RedisStreamBroker
4. No application code changes required!

```haxe
// Before
collection.addSingleton(IStreamBroker, LocalStreamBroker);

// After
collection.addSingleton(IStreamBroker, RedisStreamBroker);
```

## Performance Considerations

### LocalStreamBroker
- **Memory usage**: Scales with number of streams and messages
- **Auto-trimming**: Configured with `maxStreamLength` (default: 10,000)
- **Thread-safe**: Uses mutex for all operations
- **Best for**: Single-instance apps, development, testing

### RedisStreamBroker (Future)
- **Distributed**: Shared state across multiple servers
- **Persistence**: Messages survive application restarts
- **Scalability**: Handle millions of messages
- **Best for**: Production, multi-instance deployments

## Troubleshooting

### Messages not being processed
- Check if consumer group exists: `getGroupInfo(stream)`
- Verify consumers are reading: look for recent `lastActivity`
- Check pending messages: `xpending(stream, group)`

### High pending message count
- Consumers may be too slow
- Consider adding more consumers
- Check for exceptions preventing acknowledgment
- Use auto-claim to recover stuck messages

### Memory growth
- Streams not being trimmed
- Use `xtrim()` periodically
- Reduce `maxStreamLength` in LocalStreamBroker

## See Also

- [StreamBrokerDemo.hx](StreamBrokerDemo.hx) - Complete working examples
- [Redis Streams Documentation](https://redis.io/topics/streams-intro) - Redis Streams reference
- [IStreamBroker.hx](IStreamBroker.hx) - Full API interface definition
