package sidewinder;

import hx.injection.Service;

/**
 * Cache service interface for key-value storage with TTL support.
 * 
 * Implementations:
 * - InMemoryCacheService: Thread-safe in-memory cache with LRU eviction
 * - RedisCacheService: (Future) Distributed Redis-backed cache
 * 
 * Usage:
 * ```haxe
 * var cache = DI.get(ICacheService);
 * cache.set("user:123", userData, 3600000); // 1 hour TTL
 * var user = cache.get("user:123");
 * ```
 */
interface ICacheService extends Service {
    /**
     * Store a value in the cache with optional TTL.
     * @param key Cache key
     * @param value Value to store (any Dynamic type)
     * @param ttlMs Time-to-live in milliseconds (null = no expiration)
     */
    public function set(key:String, value:Dynamic, ?ttlMs:Int):Void;
    
    /**
     * Retrieve a value from the cache.
     * @param key Cache key
     * @return The cached value, or null if not found or expired
     */
    public function get(key:String):Null<Dynamic>;
    
    /**
     * Get cached value or compute and cache it if missing.
     * @param key Cache key
     * @param computeFn Function to compute the value if not cached
     * @param ttlMs Time-to-live in milliseconds (null = no expiration)
     * @return The cached or computed value
     */
    public function getOrCompute(key:String, computeFn:Void->Dynamic, ?ttlMs:Int):Dynamic;
    
    /**
     * Remove all expired entries from the cache.
     * This is called automatically by background sweeper threads in some implementations.
     */
    public function sweepExpired():Void;
}
