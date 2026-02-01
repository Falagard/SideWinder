# Cache System Architecture

## Overview

The SideWinder cache system uses an interface-based design that allows swapping between different cache implementations without changing application code.

## Architecture

```
ICacheService (interface)
├── InMemoryCacheService (thread-safe, LRU, production-ready)
└── RedisCacheService (distributed, template/placeholder)
```

## Interface: `ICacheService`

The cache interface defines four core operations:

```haxe
interface ICacheService extends Service {
    function set(key:String, value:Dynamic, ?ttlMs:Int):Void;
    function get(key:String):Null<Dynamic>;
    function getOrCompute(key:String, computeFn:Void->Dynamic, ?ttlMs:Int):Dynamic;
    function sweepExpired():Void;
}
```

### Methods

- **`set(key, value, ?ttlMs)`**: Store a value with optional time-to-live in milliseconds
- **`get(key)`**: Retrieve a value; returns `null` if not found or expired
- **`getOrCompute(key, computeFn, ?ttlMs)`**: Get cached value or compute and cache if missing
- **`sweepExpired()`**: Clean up expired entries (implementation-specific)

## Implementations

### InMemoryCacheService

**Status**: Production-ready ✅

A high-performance, thread-safe in-memory cache with:

- **Sharding**: 16 shards to reduce lock contention
- **LRU Eviction**: Least Recently Used policy with doubly-linked lists
- **Thread Safety**: Per-shard mutexes for concurrent access
- **Auto-cleanup**: Background thread sweeps expired entries every 60 seconds
- **Capacity**: 512 entries per shard (8192 total by default)

**Configuration**:
```haxe
DI.init(c -> {
    c.addSingleton(ICacheService, InMemoryCacheService);
});
```

**Best for**:
- Single-server deployments
- Low to medium cache volumes (< 100K entries)
- Fast local access requirements

### RedisCacheService

**Status**: Template/Placeholder 🚧

A distributed cache implementation backed by Redis (not yet implemented).

**Planned features**:
- Distributed caching across multiple servers
- Connection pooling
- Automatic reconnection
- Atomic operations using Lua scripts
- TTL mapping to Redis EXPIRE

**Configuration** (future):
```haxe
DI.init(c -> {
    c.addSingleton(ICacheService, RedisCacheService);
});
```

**Best for** (when implemented):
- Multi-server deployments
- Large cache volumes (> 100K entries)
- Shared cache across application instances
- Cache persistence requirements

## Usage Examples

### Basic Usage

```haxe
var cache = DI.get(ICacheService);

// Store with 1 hour TTL
cache.set("user:123", userData, 3600000);

// Retrieve
var user = cache.get("user:123");
if (user != null) {
    trace("Cache hit!");
}
```

### Compute-on-Miss Pattern

```haxe
var cache = DI.get(ICacheService);

// Get from cache or compute if missing
var expensiveData = cache.getOrCompute("report:2025-01", () -> {
    // This only runs on cache miss
    return generateMonthlyReport(2025, 1);
}, 86400000); // 24 hour TTL
```

### Service Integration

```haxe
class UserService implements IUserService {
    private var cache:ICacheService;
    
    public function new() {
        this.cache = DI.get(ICacheService);
    }
    
    public function getUserById(id:Int):User {
        return cache.getOrCompute('user:$id', () -> {
            return database.query("SELECT * FROM users WHERE id = ?", [id])[0];
        }, 300000); // 5 minute TTL
    }
}
```

## Switching Implementations

To switch from in-memory to Redis (once implemented):

### Before:
```haxe
DI.init(c -> {
    c.addSingleton(ICacheService, InMemoryCacheService);
});
```

### After:
```haxe
DI.init(c -> {
    c.addSingleton(ICacheService, RedisCacheService);
});
```

**No other code changes needed!** All services using `ICacheService` will automatically use the new implementation.

## Implementation Guidelines

When creating a new cache implementation:

1. **Implement `ICacheService`**: All four methods must be implemented
2. **Handle TTL properly**: `null` means no expiration
3. **Thread safety**: Ensure thread-safe operations if used in multi-threaded context
4. **Return types**: `get()` must return `null` for missing/expired keys
5. **Error handling**: Handle errors gracefully, prefer returning `null` over throwing

### Example Template:

```haxe
class MyCacheService implements ICacheService {
    public function new() {
        // Initialize
    }
    
    public function set(key:String, value:Dynamic, ?ttlMs:Int):Void {
        // Store with optional TTL
    }
    
    public function get(key:String):Null<Dynamic> {
        // Retrieve, return null if not found/expired
    }
    
    public function getOrCompute(key:String, computeFn:Void->Dynamic, ?ttlMs:Int):Dynamic {
        var cached = get(key);
        if (cached != null) return cached;
        
        var computed = computeFn();
        set(key, computed, ttlMs);
        return computed;
    }
    
    public function sweepExpired():Void {
        // Clean up expired entries
    }
}
```

## Performance Considerations

### InMemoryCacheService

- **Lookup**: O(1) average case
- **Insert**: O(1) average case
- **Memory**: ~1KB per entry (varies by value size)
- **Thread contention**: Low due to sharding
- **Sweep cost**: O(n) every 60 seconds

### RedisCacheService (planned)

- **Lookup**: O(1) + network latency
- **Insert**: O(1) + network latency
- **Memory**: Redis server memory
- **Network**: ~1ms local, ~10-50ms cross-region
- **Sweep cost**: Redis handles automatically

## Testing

```haxe
// Mock cache for testing
class MockCacheService implements ICacheService {
    private var storage:Map<String, Dynamic> = new Map();
    
    public function set(key:String, value:Dynamic, ?ttlMs:Int):Void {
        storage.set(key, value);
    }
    
    public function get(key:String):Null<Dynamic> {
        return storage.get(key);
    }
    
    public function getOrCompute(key:String, computeFn:Void->Dynamic, ?ttlMs:Int):Dynamic {
        var val = get(key);
        return val != null ? val : (set(key, val = computeFn()), val);
    }
    
    public function sweepExpired():Void {}
}
```

## Future Enhancements

1. **RedisCacheService**: Complete implementation with Redis client
2. **MemcachedCacheService**: Memcached backend
3. **TieredCacheService**: L1 (memory) + L2 (Redis) cache
4. **Cache statistics**: Hit rate, miss rate, eviction count
5. **Cache warming**: Preload commonly accessed data
6. **Distributed invalidation**: Pub/sub for cache invalidation across servers
