import sys.thread.Mutex;
import sys.thread.Thread;
import haxe.ds.StringMap;
import Date;
import Sys;

typedef Entry = {
    var key:String;
    var value:Dynamic;
    var expiresAt:Null<Float>;
    var prev:Null<Entry>;
    var next:Null<Entry>;
};

// Shard of the cache
// This allows us to reduce lock contention by partitioning the cache into multiple independent shards
private class Shard {
    public var mutex:Mutex;
    public var map:StringMap<Entry>;
    public var head:Null<Entry>;
    public var tail:Null<Entry>;
    public var maxEntries:Int;

    public function new(maxEntries:Int) {
        this.mutex = new Mutex();
        this.map = new StringMap<Entry>();
        this.head = null;
        this.tail = null;
        this.maxEntries = maxEntries;
    }
}

/**
 * Thread-safe, sharded LRU + TTL cache.
 */
class Cache {


    private var shards:Array<Shard>;
    private var shardCount:Int;

    public function new(shardCount:Int = 16, maxEntriesPerShard:Int = 512) {
        this.shardCount = shardCount;
        this.shards = [];
        for (i in 0...shardCount)
            shards.push(new Shard(maxEntriesPerShard));

        // start TTL sweeper thread
        Thread.create(() -> {
            while (true) {
                Sys.sleep(60); // once per minute
                sweepExpired();
            }
        });
    }

    private inline function shardFor(key:String):Shard {
        var idx = (haxe.crypto.Md5.encode(key).charCodeAt(0) & 0xFF) % shardCount;
        return shards[idx];
    }

    // Move entry to head of LRU list
    private function moveToHead(shard:Shard, e:Entry):Void {
        if (shard.head == e) return;
        // unlink
        if (e.prev != null) e.prev.next = e.next;
        if (e.next != null) e.next.prev = e.prev;
        if (shard.tail == e) shard.tail = e.prev;

        // move to head
        e.prev = null;
        e.next = shard.head;
        if (shard.head != null) shard.head.prev = e;
        shard.head = e;
        if (shard.tail == null) shard.tail = e;
    }

    private function insertAtHead(shard:Shard, e:Entry):Void {
        e.prev = null;
        e.next = shard.head;
        if (shard.head != null) shard.head.prev = e;
        shard.head = e;
        if (shard.tail == null) shard.tail = e;
    }

    private function removeTail(shard:Shard):Void {
        var tail = shard.tail;
        if (tail == null) return;
        shard.map.remove(tail.key);
        if (tail.prev != null) tail.prev.next = null;
        shard.tail = tail.prev;
        if (shard.tail == null) shard.head = null;
    }

    public function set(key:String, value:Dynamic, ttlMs:Null<Int> = null):Void {
        var shard = shardFor(key);
        shard.mutex.acquire();
        try {
            var e = shard.map.get(key);
            var expires = (ttlMs == null ? null : Date.now().getTime() + ttlMs);

            if (e != null) {
                e.value = value;
                e.expiresAt = expires;
                moveToHead(shard, e);
                shard.mutex.release();
                return;
            }

            e = { key: key, value: value, expiresAt: expires, prev: null, next: null };

            shard.map.set(key, e);
            insertAtHead(shard, e);

            // Evict if too large
            var count = 0;
            var it = shard.map.keys();
            while (it.hasNext()) {
                it.next();

                count++;
            }
            if (count > shard.maxEntries)
                removeTail(shard);

            shard.mutex.release();
        } catch(e) {
            shard.mutex.release();
        }
    }

    public function get(key:String):Null<Dynamic> {
        var shard = shardFor(key);
        shard.mutex.acquire();
        try {
            var e = shard.map.get(key);
            if (e == null)
            {
                shard.mutex.release();
            } return null;

            // check TTL
            if (e.expiresAt != null && e.expiresAt <= Date.now().getTime()) {
                removeEntry(shard, e);
                shard.mutex.release();
                return null;
            }

            moveToHead(shard, e);
            shard.mutex.release();
            return e.value;
        } catch(e) {
            shard.mutex.release();
            return null;
        }
    }

    public function getOrCompute(key:String, computeFn:Void->Dynamic, ?ttlMs:Int):Dynamic {
        var shard = shardFor(key);
        shard.mutex.acquire();
        try {
            var e = shard.map.get(key);
            if (e != null) {
                if (e.expiresAt == null || e.expiresAt > Date.now().getTime()) {
                    moveToHead(shard, e);
                    shard.mutex.release();
                    return e.value;
                } else {
                    removeEntry(shard, e);
                }
            }

            var val = computeFn();
            set(key, val, ttlMs);
            shard.mutex.release();
            return val;
        } catch(e) {
            shard.mutex.release();
            return null;
        }
    }

    private function removeEntry(shard:Shard, e:Entry):Void {
        shard.map.remove(e.key);
        if (e.prev != null) e.prev.next = e.next;
        if (e.next != null) e.next.prev = e.prev;
        if (shard.head == e) shard.head = e.next;
        if (shard.tail == e) shard.tail = e.prev;
    }

    public function sweepExpired():Void {
        var now = Date.now().getTime();
        for (shard in shards) {
            shard.mutex.acquire();
            try {
                var it = shard.map.keys();
                var expired = [];
                while (it.hasNext()) {
                    var k = it.next();
                    var e = shard.map.get(k);
                    if (e != null && e.expiresAt != null && e.expiresAt <= now)
                        expired.push(e);
                }
                for (e in expired) removeEntry(shard, e);
            
                shard.mutex.release();
            } catch(e) {
                shard.mutex.release();
            }
        }
    }
}
