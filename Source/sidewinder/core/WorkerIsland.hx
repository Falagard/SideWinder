package sidewinder.core;
#if (html5 && !sys)
#error "WorkerIsland is not available on HTML5."
#end

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.logging.HybridLogger;
import sys.thread.Thread;
import sys.thread.Mutex;

/**
 * A dedicated request processing thread (Logic Island).
 * Processes a queue of requests independently from the main loop and other islands.
 */
class WorkerIsland {
	public var id(default, null):Int;

	private var requestQueue:Array<IslandRequest> = [];
	private var queueMutex:Mutex = new Mutex();
	private var running:Bool = false;
	private var processor:IslandRequest->Void;

	public function new(id:Int, processor:IslandRequest->Void) {
		this.id = id;
		this.processor = processor;
	}

	/**
	 * Start the background thread for this island.
	 */
	public function start(?onThreadStart:() -> Void):Void {
		if (running) return;
		running = true;

		Thread.create(() -> {
			if (onThreadStart != null) {
				onThreadStart();
			}
			HybridLogger.info('[WorkerIsland $id] Logic thread started');
			while (running) {
				var req = nextRequest();
				if (req != null) {
					try {
						processor(req);
					} catch (e:Dynamic) {
						HybridLogger.error('[WorkerIsland $id] Error processing request: ' + e);
					}
				} else {
					// Sleep briefly to prevent tight loop when idle
					#if !html5
					Sys.sleep(0.001);
					#end
				}
			}
		});
	}

	public function stop():Void {
		running = false;
	}

	/**
	 * Enqueue a request to be processed by this island.
	 */
	public function enqueue(req:IslandRequest):Void {
		queueMutex.acquire();
		requestQueue.push(req);
		queueMutex.release();
	}

	private function nextRequest():Null<IslandRequest> {
		var req:Null<IslandRequest> = null;
		queueMutex.acquire();
		if (requestQueue.length > 0) {
			req = requestQueue.shift();
		}
		queueMutex.release();
		return req;
	}

	public function getLoad():Int {
		queueMutex.acquire();
		var count = requestQueue.length;
		queueMutex.release();
		return count;
	}
}

/**
 * Generic container for a request dispatched to an island.
 */
typedef IslandRequest = {
	/**
	 * The session ID used for stickiness.
	 */
	var sessionId:Null<String>;

	/**
	 * The actual work to perform.
	 */
	var work:Void->Void;
}
