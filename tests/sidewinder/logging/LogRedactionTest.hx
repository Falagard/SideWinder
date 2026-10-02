package sidewinder.logging;

import utest.Assert;
import utest.Test;

class LogRedactionTest extends Test {
	function testCredentialHeadersAreMaskedCaseInsensitively() {
		var h = new Map<String, String>();
		h.set("Host", "example.com");
		h.set("Cookie", "session=abc123");
		h.set("authorization", "Bearer secret-token");
		h.set("X-Project-Key", "pk_live_1");
		h.set("Stripe-Signature", "t=1,v1=deadbeef");
		var s = LogRedaction.headerSummary(h);
		Assert.isTrue(s.indexOf("Host: example.com") >= 0);
		for (secret in ["abc123", "secret-token", "pk_live_1", "deadbeef"]) Assert.isTrue(s.indexOf(secret) < 0, secret);
		Assert.isTrue(s.indexOf("Cookie: [redacted]") >= 0);
		Assert.isTrue(s.indexOf("authorization: [redacted]") >= 0);
	}

	function testRawHeaderBlockIsMasked() {
		var raw = "GET /x HTTP/1.1\r\nHost: a\r\nCookie: session=abc123\r\nauthorization: Bearer tok\r\nAccept: */*";
		var out = LogRedaction.rawHeaderBlock(raw);
		Assert.equals("GET /x HTTP/1.1\r\nHost: a\r\nCookie: [redacted]\r\nauthorization: [redacted]\r\nAccept: */*", out);
		Assert.equals("", LogRedaction.rawHeaderBlock(null));
	}

	function testNullHeaders() {
		Assert.equals("", LogRedaction.headerSummary(null));
	}

	function testDebugGateFollowsMinimumLevel() {
		// ERROR is never below the minimum level, whatever init() was given.
		Assert.isTrue(HybridLogger.isEnabled(HybridLogger.LogLevel.ERROR));
	}
}
