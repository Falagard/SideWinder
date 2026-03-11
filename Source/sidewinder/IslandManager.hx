package sidewinder;

import sys.thread.Thread;
import haxe.crypto.Md5;
import sidewinder.WorkerIsland;

/**
 * Manages a pool of WorkerIslands and handles request distribution.
 * Implements "Stickiness" based on session ID to ensure deterministic state per user.
 */
class IslandManager {
	private var islands:Array<WorkerIsland> = [];
	private var numIslands:Int;
	private var roundRobinCounter:Int = 0;

	public function new(numIslands:Int) {
		this.numIslands = numIslands;
		init();
	}

	private function init():Void {
		HybridLogger.info('[IslandManager] Initializing $numIslands logic islands');
		for (i in 0...numIslands) {
			var island = new WorkerIsland(i, (req) -> {
				req.work();
			});
			islands.push(island);
			island.start();
		}
	}

	/**
	 * Dispatch a request to an island.
	 * @param sessionId Optional session ID for sticky routing.
	 * @param work The request handling logic to execute.
	 */
	public function dispatch(sessionId:Null<String>, work:Void->Void):Void {
		var island:WorkerIsland;

		if (sessionId != null && sessionId != "") {
			// Sticky routing: Same session -> Same island
			var hash = Md5.encode(sessionId);
			var index = hash.charCodeAt(0) % numIslands;
			island = islands[index];
		} else {
			// Round-robin for anonymous requests
			island = islands[roundRobinCounter % numIslands];
			roundRobinCounter++;
		}

		island.enqueue({
			sessionId: sessionId,
			work: work
		});
	}

	/**
	 * Stop all islands.
	 */
	public function shutdown():Void {
		for (island in islands) {
			island.stop();
		}
	}

	public function getIslandCount():Int return numIslands;
	
	public function getLoadInfo():Array<Int> {
		return islands.map(i -> i.getLoad());
	}
}
