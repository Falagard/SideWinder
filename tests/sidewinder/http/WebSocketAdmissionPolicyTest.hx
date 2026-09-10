package sidewinder.http;

import utest.Assert;
import utest.Test;

class WebSocketAdmissionPolicyTest extends Test {
	function testGrantsUpToTheLimitThenRefuses() {
		var p = new WebSocketAdmissionPolicy(3);
		Assert.isTrue(p.tryAcquire());
		Assert.isTrue(p.tryAcquire());
		Assert.isTrue(p.tryAcquire());
		Assert.isFalse(p.tryAcquire());
		Assert.equals(3, p.getActive());
		Assert.equals(1, p.refusedCount);
	}

	function testReleaseFreesASlot() {
		var p = new WebSocketAdmissionPolicy(1);
		Assert.isTrue(p.tryAcquire());
		Assert.isFalse(p.tryAcquire());
		p.release();
		Assert.equals(0, p.getActive());
		Assert.isTrue(p.tryAcquire());
	}

	// HxWell fires its close path twice on a clean close handshake, so a double
	// release must not drive the count negative and hand out a phantom slot.
	function testDoubleReleaseFloorsAtZero() {
		var p = new WebSocketAdmissionPolicy(2);
		p.tryAcquire();
		p.release();
		p.release();
		p.release();
		Assert.equals(0, p.getActive());
		Assert.isTrue(p.tryAcquire());
		Assert.isTrue(p.tryAcquire());
		Assert.isFalse(p.tryAcquire());
	}

	function testTracksPeak() {
		var p = new WebSocketAdmissionPolicy(4);
		p.tryAcquire(); p.tryAcquire(); p.tryAcquire();
		p.release();
		Assert.equals(3, p.peakActive);
		Assert.equals(2, p.getActive());
	}

	function testZeroLimitRefusesEverything() {
		var p = new WebSocketAdmissionPolicy(0);
		Assert.isFalse(p.tryAcquire());
	}

	function testNegativeLimitIsRejected() {
		Assert.raises(function() new WebSocketAdmissionPolicy(-1), String);
	}
}
