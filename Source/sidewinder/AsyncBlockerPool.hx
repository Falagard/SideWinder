package sidewinder;

import sys.thread.Lock;
import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Deque;

class AsyncBlockerPool {
	static var pool:Deque<ThreadTask> = new Deque();
	static var mutex = new Mutex();
	static var running = false;
	static var maxThreads = 4;

	private static function init() {
		if (running)
			return;
		running = true;
		for (i in 0...maxThreads)
			Thread.create(workerLoop);
	}

	private static function workerLoop() {
		while (true) {
			var task:ThreadTask = null;
			mutex.acquire();
			task = pool.pop(false);
			mutex.release();

			if (task == null) {
				Sys.sleep(0.01);
				continue;
			}

			try {
				task.run();
			} catch (e) {
				task.fail('Exception: $e');
			}
		}
	}

	public static function run<T>(fn:(cb:(T) -> Void)->Void, timeoutSeconds:Float = 0):T {
		init();

		var lock = new Lock();
		var result:T = null;
		var done = false;
		var task = new ThreadTask(() -> {
			fn(value -> {
				result = value;
				done = true;
				lock.release();
			});
		});

		mutex.acquire();
		pool.add(task);
		mutex.release();

		var start = Sys.time();
		while (!done) {
			lock.wait(0.05);
			if (timeoutSeconds > 0 && Sys.time() - start > timeoutSeconds)
				throw 'AsyncBlockerPool timeout after ${timeoutSeconds}s';
		}

		return result;
	}
}

private class ThreadTask {
	var work:Void->Void;

	public function new(work:Void->Void)
		this.work = work;

	public function run()
		work();

	public function fail(msg:String)
		trace(msg);
}
