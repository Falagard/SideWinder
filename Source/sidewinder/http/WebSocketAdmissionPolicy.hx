package sidewinder.http;

// SIDEWINDER-CORE-DECOUPLING-S1 (Task K, enforcement half).
//
// Counts live WebSocket connections and refuses upgrades past the configured
// ceiling, so long-lived WebSockets can never consume the worker pool's HTTP
// headroom.
//
// `HttpServerOptions` guarantees the pool is large enough for
// `maxWebSocketConnections` sockets PLUS `httpWorkerHeadroom` HTTP workers;
// this class guarantees the first number is actually respected at runtime.
// Together they make the "10 WebSocket clients deadlock the server" failure
// structurally impossible rather than merely documented.
//
// Thread-safe: `tryAcquire`/`release` are called from the accept loop's worker
// threads.
class WebSocketAdmissionPolicy {
	final limit:Int;
	final mutex = new sys.thread.Mutex();
	var active:Int = 0;

	/** Highest concurrent count observed. Diagnostics/tests only. */
	public var peakActive(default, null):Int = 0;

	/** Number of upgrades refused because the ceiling was reached. */
	public var refusedCount(default, null):Int = 0;

	public function new(limit:Int) {
		if (limit < 0)
			throw "WebSocketAdmissionPolicy: limit must be >= 0";
		this.limit = limit;
	}

	public function getLimit():Int {
		return limit;
	}

	public function getActive():Int {
		mutex.acquire();
		var n = active;
		mutex.release();
		return n;
	}

	/**
	 * Reserve a slot for a new WebSocket connection.
	 * @return true if the connection may proceed; false if it must be refused.
	 */
	public function tryAcquire():Bool {
		mutex.acquire();
		var granted = active < limit;
		if (granted) {
			active++;
			if (active > peakActive)
				peakActive = active;
		} else {
			refusedCount++;
		}
		mutex.release();
		return granted;
	}

	/**
	 * Release a slot. Safe to call more than once for the same connection --
	 * HxWell's `SocketWebSocketHandler` fires its close path twice on a clean
	 * close handshake, so callers are expected to guard with their own
	 * "already released" flag; this floor at zero is a second line of defence,
	 * not a substitute for it.
	 */
	public function release():Void {
		mutex.acquire();
		if (active > 0)
			active--;
		mutex.release();
	}
}
