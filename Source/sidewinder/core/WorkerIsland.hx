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
	// SIDEWINDER-CORE-DECOUPLING-S1 (Task L): the idle loop used to
	// `Sys.sleep(0.001)`, i.e. ~1000 wakeups/second per island, forever. On an
	// SBC sharing a core with a realtime audio thread that is a real
	// scheduling-jitter source. `sys.thread.Lock` is a counting semaphore on
	// every threaded sys target, so an enqueue that happens while the worker is
	// not parked still wakes the next wait() -- no lost wakeups. The 1s timeout
	// bounds the cost of any missed signal and keeps `running` polled for
	// shutdown.
	#if !html5
	private var taskSignal:sys.thread.Lock = new sys.thread.Lock();
	#end
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
					// Block until work arrives (or 1s elapses) rather than
					// spinning -- see taskSignal's declaration.
					#if !html5
					taskSignal.wait(1.0);
					#end
				}
			}
		});
	}

	public function stop():Void {
		running = false;
		// Wake the worker so it observes !running and exits promptly.
		#if !html5
		taskSignal.release();
		#end
	}

	/**
	 * Enqueue a request to be processed by this island.
	 */
	public function enqueue(req:IslandRequest):Void {
		queueMutex.acquire();
		requestQueue.push(req);
		queueMutex.release();
		#if !html5
		taskSignal.release();
		#end
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
