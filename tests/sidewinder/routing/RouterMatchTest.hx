package sidewinder.routing;

import sidewinder.routing.Router.Request;
// `Route` is a secondary type inside the Router module -- it must be imported
// as Module.Type, not by bare name (CLAUDE.md: "Haxe requires the Module.Type form").
import sidewinder.routing.Router.Route;
import utest.Assert;
import utest.Test;

/**
 * Route matching has never had a test. The pedal conformance fixture initially
 * used `{value}` syntax and silently 404'd -- SideWinder matches `:value`.
 * These lock the actual grammar down.
 */
class RouterMatchTest extends Test {
	function req(method:String, path:String):Request {
		return {
			method: method, path: path,
			headers: new Map(), query: new Map(), params: new Map(),
			body: "", jsonBody: null, formBody: new haxe.ds.StringMap(),
			cookies: new haxe.ds.StringMap(), files: []
		};
	}

	function testColonSyntaxIsThePathParamGrammar() {
		var r = new Route("GET", "/echo/:value", null);
		var m = r.matches("/echo/hello");
		Assert.notNull(m);
		Assert.equals("hello", m.get("value"));
	}

	function testBraceSyntaxIsNotSupported() {
		// Documents the trap explicitly: `{value}` is a literal, not a param.
		var r = new Route("GET", "/echo/{value}", null);
		Assert.isNull(r.matches("/echo/hello"));
		Assert.notNull(r.matches("/echo/{value}"));
	}

	function testMultipleParams() {
		var r = new Route("GET", "/p/:projectId/w/:workspaceId", null);
		var m = r.matches("/p/abc/w/def");
		Assert.notNull(m);
		Assert.equals("abc", m.get("projectId"));
		Assert.equals("def", m.get("workspaceId"));
	}

	function testSingleSegmentParamDoesNotSpanSlashes() {
		var r = new Route("GET", "/files/:name", null);
		Assert.isNull(r.matches("/files/a/b"));
	}

	function testCatchAllSpansSlashes() {
		var r = new Route("GET", "/files/:*rest", null);
		var m = r.matches("/files/a/b/c");
		Assert.notNull(m);
		Assert.equals("a/b/c", m.get("rest"));
	}

	function testNonMatchingPathReturnsNull() {
		var r = new Route("GET", "/health", null);
		Assert.isNull(r.matches("/healthz"));
		Assert.isNull(r.matches("/health/x"));
	}

	/**
	 * CONCURRENCY REGRESSION. A `Route` is shared -- `Router.instance` is a static singleton
	 * holding one Route per template -- so every concurrent request to a template matches
	 * through the SAME object. `Route` used to keep one `EReg` as an instance field, and `EReg`
	 * stores its capture groups inside the instance: `match()` writes them, `matched()` reads
	 * them back. Two threads therefore interleaved as match(A) -> match(B) -> matched()=B for
	 * BOTH, silently handing one request another caller's path parameter.
	 *
	 * This was not theoretical. In the consuming server two concurrent POSTs to the same
	 * template, each sent once with a distinct id, were dispatched as the SAME id twice: one
	 * resource was processed twice and the other never, while both callers received HTTP 200.
	 *
	 * Fixed by building the matcher inside `matches()` so capture state is request-local.
	 * This test fails at ~33% cross-assignment against the shared-EReg implementation.
	 */
	function testConcurrentMatchesKeepPathParamsRequestLocal() {
		var route = new Route("POST", "/test/:id", null);

		var threads = 8;
		var rounds = 400;
		var lock = new sys.thread.Mutex();
		var mismatches = 0;
		var attempts = 0;
		var finished = 0;
		var firstSample:String = null;

		// Worker identity is passed as an ARGUMENT, never captured from a loop variable, so a
		// clean result cannot come from every thread sharing one id.
		var spawn = function(workerId:Int):Void {
			sys.thread.Thread.create(function() {
				var localMismatch = 0;
				var localAttempts = 0;
				var localSample:String = null;
				for (round in 0...rounds) {
					localAttempts++;
					var expected = "w" + workerId + "r" + round;
					var m = route.matches("/test/" + expected);
					var actual = m == null ? null : m.get("id");
					if (actual != expected) {
						localMismatch++;
						if (localSample == null)
							localSample = "sent id=" + expected + " but matched id=" + actual;
					}
				}
				lock.acquire();
				mismatches += localMismatch;
				attempts += localAttempts;
				if (firstSample == null) firstSample = localSample;
				finished++;
				lock.release();
			});
		};
		for (w in 0...threads) spawn(w);

		var waitedMs = 0;
		while (true) {
			lock.acquire();
			var done = finished;
			lock.release();
			if (done == threads) break;
			if (waitedMs > 120000) break;
			Sys.sleep(0.01);
			waitedMs += 10;
		}

		lock.acquire();
		var finalFinished = finished;
		var finalAttempts = attempts;
		var finalMismatches = mismatches;
		var sample = firstSample;
		lock.release();

		// Harness invariants first: a zero-mismatch result must not be obtainable from threads
		// that never ran or never finished.
		Assert.equals(threads, finalFinished, "all matcher threads must finish");
		Assert.equals(threads * rounds, finalAttempts, "every match must actually be attempted");

		Assert.equals(0, finalMismatches,
			"concurrent matches on one route template must keep path params request-local; "
			+ finalMismatches + " of " + (threads * rounds) + " cross-assigned. First: " + sample);
	}

	/** Control: sequential matching is correct, so a failure above is concurrency-only. */
	function testSingleThreadedMatchingIsStable() {
		var route = new Route("POST", "/test/:id", null);
		for (i in 0...200) {
			var m = route.matches("/test/id-" + i);
			Assert.notNull(m);
			Assert.equals("id-" + i, m.get("id"));
		}
	}

}
