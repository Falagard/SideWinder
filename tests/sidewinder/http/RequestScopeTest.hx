package sidewinder.http;

import utest.Assert;
import utest.Test;

class RequestScopeTest extends Test {
	// A route must be servable with no DI container anywhere in the program.
	function testMapScopeNeedsNoContainer() {
		var scope = new MapRequestScopeFactory().create("req-1");
		Assert.equals("req-1", scope.requestId);
		Assert.isNull(scope.unwrap());
		scope.setAttribute("tenant", "acme");
		Assert.equals("acme", scope.getAttribute("tenant"));
		scope.dispose();
		Assert.isNull(scope.getAttribute("tenant"));
	}

	function testSequentialRequestIdsAreUniqueAndOrdered() {
		var f = new SequentialRequestIdFactory("test");
		Assert.equals("test-1", f.generate());
		Assert.equals("test-2", f.generate());
		Assert.equals("test-3", f.generate());
	}

	function testGeneratedPrefixesDifferAcrossFactories() {
		var seen = new Map<String, Bool>();
		var collisions = 0;
		for (i in 0...20) {
			var id = new SequentialRequestIdFactory().generate();
			if (seen.exists(id)) collisions++;
			seen.set(id, true);
		}
		// 6 random hex chars: collisions across 20 factories should be rare, and
		// certainly not systematic.
		Assert.isTrue(collisions <= 1, 'expected at most 1 collision, got $collisions');
	}
}
