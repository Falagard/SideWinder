# Single-Threaded Queue Architecture

## Overview

Both CivetWeb and SnakeServer implementations now use a **single-threaded queue-based architecture** to ensure all Haxe request handling happens on one thread, eliminating race conditions and simplifying debugging.

## Visual Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Requests                           │
│                    (HTTP Traffic)                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│      Server Thread Pool (CivetWeb or SnakeServer)           │
│          (4 threads - Accept Connections)                    │
└───────┬──────────┬──────────┬──────────┬───────────────────┘
        │          │          │          │
        ▼          ▼          ▼          ▼
    Thread 1   Thread 2   Thread 3   Thread 4
        │          │          │          │
        └──────────┴──────────┴──────────┘
                       │
                       │ enqueueRequest()
                       │ (Thread → Queue)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Mutex-Protected Request Queue                   │
│    [Req1, Req2, Req3, Req4, ...]                            │
│    (Thread-safe buffer - same for both implementations)     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ handleRequest() → processQueue()
                       │ (Called from main loop)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│           SINGLE HAXE THREAD (Main Loop)                     │
│                                                              │
│  1. Dequeue all requests                                    │
│  2. Process each request sequentially:                      │
│     - Parse request                                          │
│     - Route via Router                                       │
│     - Call handler (thread-safe!)                           │
│     - Log response                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### CivetWeb Adapter
- C threads call `enqueueRequest()` callback
- Returns immediate 202 response
- Queue processed in `handleRequest()`

### SnakeServer Adapter
- Snake-server threads enqueue via `SnakeServerAdapter.instance`
- Returns immediate 202 response  
- `server.handleRequest()` accepts connections
- `processQueue()` handles all queued requests

**Both use identical queue architecture!**

## Key Characteristics

### Multi-Threaded Layer (C)
- **CivetWeb runs 4 C threads** for accepting connections
- Each thread handles network I/O independently
- Calls `enqueueRequest()` callback
- Returns immediate 202 response (non-blocking)

### Single-Threaded Layer (Haxe)
- **All request processing on main thread**
- `handleRequest()` called in main loop
- Processes queue sequentially
- No race conditions possible
- Simpler debugging and state management

## Benefits

### ✅ Thread Safety
- No mutex needed in Haxe handlers
- No race conditions
- No deadlocks
- Simple, predictable execution

### ✅ Performance
- C threads handle network efficiently
- Haxe processing doesn't block C thredads
- Queue buffers bursts of traffic
- Good throughput for most workloads

### ✅ Simplicity
- Easy to reason about
- Sequential execution in handlers
- Standard debugging tools work
- No thread coordination needed

## Tradeoffs

### ⚠️ Latency
- 202 response is immediate
- Actual processing happens asynchronously
- Suitable for fire-and-forget patterns
- Not ideal for request/response where client waits

### ⚠️ Throughput Limit
- Single thread processes all requests
- Limited by main loop frequency
- Good for moderate traffic (<1000 req/sec)
- Consider multi-threaded for extreme loads

## Code Flow

### C Thread (enqueueRequest)
```haxe
// Called from any C thread
queueMutex.acquire();
requestQueue.push(request);  // Add to queue
queueMutex.release();
return { statusCode: 202 };  // Immediate response
```

### Main Thread (handleRequest)
```haxe
// Called from main loop only
queueMutex.acquire();
var requests = requestQueue.copy();
requestQueue = [];
queueMutex.release();

// Process sequentially - single thread!
for (req in requests) {
    var response = router.route(req);
    log(req, response);
}
```

## Comparison to Other Patterns

### vs Fully Multi-Threaded
| Aspect | Single-Threaded Queue | Multi-Threaded |
|--------|---------------------|----------------|
| Complexity | ⭐ Simple | ⭐⭐⭐⭐ Complex |
| Thread Safety | ✅ Automatic | ❌ Manual mutexes |
| Debugging | ✅ Easy | ❌ Difficult |
| Throughput | Good | Excellent |
| Latency | Good | Better |

### vs Fully Single-Threaded
| Aspect | Single-Threaded Queue | Fully Single |
|--------|---------------------|--------------|
| Network I/O | ✅ Non-blocking (C) | ❌ Blocking |
| Connection Handling | ✅ Concurrent | ❌ Sequential |
| Scalability | Good | Limited |

## When to Use This Pattern

### ✅ Good For
- Web APIs with moderate traffic
- CRUD applications
- Admin interfaces
- Internal tools
- Most business applications

### ❌ Consider Alternatives For
- Real-time streaming
- WebSocket servers
- Very high throughput needs (>10K req/sec)
- Long-polling where client blocks

## Configuration

### Queue Size
No hard limit - grows dynamically. Monitor queue length:
```haxe
HybridLogger.debug('Queue length: ${requestQueue.length}');
```

### Processing Frequency
Controlled by main loop update rate. Call `handleRequest()` more frequently for lower latency.

## Monitoring

### Queue Metrics
```haxe
// Add to handleRequest()
if (requests.length > 100) {
    HybridLogger.warn('Large queue: ${requests.length} requests');
}
```

### Processing Time
```haxe
var start = Date.now().getTime();
processRequest(req);
var duration = Date.now().getTime() - start;
if (duration > 100) {
    HybridLogger.warn('Slow handler: ${duration}ms');
}
```

## Summary

This architecture provides the best of both worlds:
- **C threads** handle network efficiently
- **Single Haxe thread** keeps code simple and safe
- **Queue** buffers traffic and decouples layers
- **Good performance** for typical web applications

Perfect for SideWinder's use case! 🎯
