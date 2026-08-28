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
}
