package sidewinder.http;

import utest.Assert;
import utest.Test;

class HttpServerOptionsTest extends Test {
	function testDefaultPoolIsDerivedFromTheWebSocketCeiling() {
		var o = new HttpServerOptions("127.0.0.1", 8080, {maxWebSocketConnections: 16, httpWorkerHeadroom: 8});
		Assert.equals(24, o.workerPoolSize);
	}

	// The defect this class exists to prevent: HxWell's own default pool is 10,
	// and 10 concurrent WebSocket clients then deadlock the server outright.
	function testRejectsAPoolTooSmallForItsWebSocketCeiling() {
		Assert.raises(function() {
			new HttpServerOptions("127.0.0.1", 8080, {
				maxWebSocketConnections: 16,
				httpWorkerHeadroom: 8,
				workerPoolSize: 10
			});
		}, String);
	}

	function testAcceptsAPoolExactlyAtTheSafeMinimum() {
		var o = new HttpServerOptions("127.0.0.1", 8080, {
			maxWebSocketConnections: 4,
			httpWorkerHeadroom: 2,
			workerPoolSize: 6
		});
		Assert.equals(6, o.workerPoolSize);
	}

	function testZeroHeadroomIsRejectedBecauseWebSocketsWouldStarveHttp() {
		Assert.raises(function() {
			new HttpServerOptions("127.0.0.1", 8080, {httpWorkerHeadroom: 0});
		}, String);
	}

	function testHttpOnlyNeedsNoWebSocketCapacity() {
		var o = HttpServerOptions.httpOnly("0.0.0.0", 9000, 12);
		Assert.equals(0, o.maxWebSocketConnections);
		Assert.equals(12, o.workerPoolSize);
	}

	function testRejectsInvalidHostAndPort() {
		Assert.raises(function() new HttpServerOptions("", 8080), String);
		Assert.raises(function() new HttpServerOptions("127.0.0.1", 0), String);
		Assert.raises(function() new HttpServerOptions("127.0.0.1", 70000), String);
	}

	function testOmittedOverridesTakeDocumentedDefaultsNotZero() {
		var o = new HttpServerOptions("127.0.0.1", 8080);
		Assert.equals(HttpServerOptions.DEFAULT_MAX_HEADER_SIZE, o.maxHeaderSize);
		Assert.equals(HttpServerOptions.DEFAULT_MAX_URL_LENGTH, o.maxUrlLength);
		Assert.equals(HttpServerOptions.DEFAULT_MAX_REQUEST_BODY_SIZE, o.maxRequestBodySize);
		Assert.equals(HttpServerOptions.DEFAULT_MAX_WS_MESSAGE_SIZE, o.maxWebSocketMessageSize);
	}
}
