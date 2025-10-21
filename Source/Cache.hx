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
        var shard:Shard;
    };

    class Shard {
        public var mutex:Mutex;
        public var map:StringMap<Entry>;
        public var locks:StringMap<Mutex>;
        public var head:Null<Entry>;
        public var tail:Null<Entry>;

        public function new() {
            mutex = new Mutex();
            map = new StringMap<Entry>();
            locks = new StringMap<Mutex>();
        }
    }

class Cache {

    

    private var shards:Array<Shard>;
    private var shardCount:Int;
    private var globalMutex:Mutex;
    private var totalEntries:Int = 0;
    private var maxEntries:Int;

    

    public function new(maxEntries:Int, shardCount:Int = 16) {
        this.shardCount = shardCount;
        this.maxEntries = maxEntries;
        this.shards = [];
        for (i in 0...shardCount) shards.push(new Shard());
        this.globalMutex = new Mutex();

        Thread.create(() -> {
            while (true) {
                Sys.sleep(60);
                sweepExpired();
            }
        });
    }

    private inline function shardFor(key:String):Shard {
        var idx = (haxe.crypto.Md5.encode(key).charCodeAt(0) & 0xFF) % shardCount;
        return shards[idx];
    }

    // LRU Helpers
    private function moveToHead(shard:Shard, e:Entry):Void {
        if (shard.head == e) return;
        if (e.prev != null) e.prev.next = e.next;
        if (e.next != null) e.next.prev = e.prev;
        if (shard.tail == e) shard.tail = e.prev;

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

    private function removeTail(shard:Shard):Null<Entry> {
        var tail = shard.tail;
        if (tail == null) return null;
        removeEntry(shard, tail);
        return tail;
    }

    // Core methods
    public function set(key:String, value:Dynamic, ttlMs:Null<Int> = null):Void {
        var shard = shardFor(key);
        var expires = (ttlMs == null ? null : Date.now().getTime() + ttlMs);

        shard.mutex.acquire();
        try {
            var e = shard.map.get(key);
            if (e != null) {
                e.value = value;
                e.expiresAt = expires;
                moveToHead(shard, e);
                return;
            }

            e = { key: key, value: value, expiresAt: expires, prev: null, next: null, shard: shard };
            shard.map.set(key, e);
            insertAtHead(shard, e);

            globalMutex.acquire();
            totalEntries++;
            var over = totalEntries > maxEntries;
            globalMutex.release();

            if (over) evictGlobal();
            shard.mutex.release();
        } catch (e) {
            shard.mutex.release();
        }
    }

    public function get(key:String):Null<Dynamic> {
        var shard = shardFor(key);
        shard.mutex.acquire();
        try {
            var e = shard.map.get(key);
            if (e == null) return null;
            if (e.expiresAt != null && e.expiresAt <= Date.now().getTime()) {
                removeEntry(shard, e);
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
        var keyLock = getKeyLock(shard, key);
        keyLock.acquire();
        try {
            var val = get(key);
            if (val != null) return val;
            val = computeFn();
            set(key, val, ttlMs);
            keyLock.release();
            cleanupKeyLock(shard, key);
            return val;

        } catch(e) {
            keyLock.release();
            cleanupKeyLock(shard, key);
            return null;
        }
    }

    private function getKeyLock(shard:Shard, key:String):Mutex {
        shard.mutex.acquire();
        try {
            var lock = shard.locks.get(key);
            if (lock == null) {
                lock = new Mutex();
                shard.locks.set(key, lock);
            }
            shard.mutex.release();
            return lock;
        } catch(e) {
            shard.mutex.release();
            return null;
        }
    }

    private function cleanupKeyLock(shard:Shard, key:String):Void {
        shard.mutex.acquire();
        try {
            shard.locks.remove(key);
            shard.mutex.release();
        } catch(e) {
            shard.mutex.release();
        }
    }

    private function removeEntry(shard:Shard, e:Entry):Void {
        shard.map.remove(e.key);
        if (e.prev != null) e.prev.next = e.next;
        if (e.next != null) e.next.prev = e.prev;
        if (shard.head == e) shard.head = e.next;
        if (shard.tail == e) shard.tail = e.prev;

        globalMutex.acquire();
        totalEntries--;
        globalMutex.release();
    }

    // 🔥 Global eviction: remove oldest entry across all shards
    private function evictGlobal():Void {
        var oldest:Null<Entry> = null;
        for (shard in shards) {
            shard.mutex.acquire();
            try {
                var t = shard.tail;
                if (t != null) {
                    if (oldest == null || (t.expiresAt ?? 0) < (oldest.expiresAt ?? 0))
                        oldest = t;
                }
                shard.mutex.release();
            } catch(e) shard.mutex.release();
        }

        if (oldest != null) {
            var shard = oldest.shard;
            shard.mutex.acquire();
            try 
            {
                removeEntry(shard, oldest);
                shard.mutex.release();
            }
            catch(e) {
                shard.mutex.release();
            }
        }
    }

    public function sweepExpired():Void {
        var now = Date.now().getTime();
        for (shard in shards) {
            shard.mutex.acquire();
            try {
                var expired:Array<Entry> = [];
                var it = shard.map.keys();
                while (it.hasNext()) {
                    var k = it.next();
                    var e = shard.map.get(k);
                    if (e != null && e.expiresAt != null && e.expiresAt <= now)
                        expired.push(e);
                }
                for (e in expired) removeEntry(shard, e);
                shard.mutex.release();
            } catch(e) shard.mutex.release();
        }
    }

    public function stats():Dynamic {
        globalMutex.acquire();
        var total = totalEntries;
        globalMutex.release();
        return {
            shards: shardCount,
            totalEntries: total,
            maxEntries: maxEntries
        };
    }
}
