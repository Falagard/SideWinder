package sidewinder.http;

/**
 * Default `IRequestIdFactory`: a process-unique, monotonically increasing id
 * with a short random prefix to keep ids distinguishable across restarts.
 *
 * Deliberately depends on nothing -- no UUID library is pulled in merely to
 * host an HTTP endpoint (SIDEWINDER-CORE-DECOUPLING-S1 Task F).
 */
class SequentialRequestIdFactory implements IRequestIdFactory {
	final prefix:String;
	final mutex = new sys.thread.Mutex();
	var counter:Int = 0;

	public function new(?prefix:String) {
		if (prefix != null) {
			this.prefix = prefix;
		} else {
			var chars = "0123456789abcdef";
			var p = "";
			for (i in 0...6)
				p += chars.charAt(Std.random(chars.length));
			this.prefix = p;
		}
	}

	public function generate():String {
		mutex.acquire();
		var n = ++counter;
		mutex.release();
		return prefix + "-" + n;
	}
}
