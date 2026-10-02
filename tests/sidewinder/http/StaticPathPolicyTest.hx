package sidewinder.http;

import utest.Assert;
import utest.Test;

/**
 * HxWellAdapter's static fallback. Before StaticPathPolicy it joined the decoded request path
 * onto the root, so `/../../secret.txt` (and its %2e%2e form, which hxwell decodes first) read
 * files outside the root, and `/project.db` downloaded a StackServerSDK app's database.
 */
class StaticPathPolicyTest extends Test {
	static inline var ROOT = "/srv/app/public";

	function testOrdinaryFilesResolveInsideTheRoot() {
		Assert.equals("/srv/app/public/index.html", StaticPathPolicy.resolve(ROOT, "/"));
		Assert.equals("/srv/app/public/index.html", StaticPathPolicy.resolve(ROOT, ""));
		Assert.equals("/srv/app/public/css/site.css", StaticPathPolicy.resolve(ROOT, "/css/site.css?v=3"));
		Assert.equals("/srv/app/public/img/logo.png", StaticPathPolicy.resolve(ROOT, "/static/img/logo.png"));
		Assert.equals("/srv/app/public/.well-known/acme-challenge/tok", StaticPathPolicy.resolve(ROOT, "/.well-known/acme-challenge/tok"));
		Assert.equals("/srv/app/public/a/b.js", StaticPathPolicy.resolve(ROOT, "/a//b.js"));
	}

	function testTraversalIsRefused() {
		// Request paths arrive already URL-decoded, so %2e%2e%2f has become ../ by now.
		for (p in ["/../../secret.txt", "/../secret.txt", "/a/../../secret.txt", "/static/../../x", "/a/b/../../../x", "/.."])
			Assert.isNull(StaticPathPolicy.resolve(ROOT, p), p);
	}

	function testDotFilesAndSensitiveFilesAreRefusedEvenInsideTheRoot() {
		for (p in ["/.env", "/.git/config", "/a/.htpasswd", "/.well-known/../.env",
				"/project.db", "/data.db", "/data.db-wal", "/tenants/t1/tenant.db", "/app.sqlite", "/server.hl",
				"/sqlite.hdll", "/server.log", "/tls/server.key", "/cert.pem", "/DATA.DB"])
			Assert.isNull(StaticPathPolicy.resolve(ROOT, p), p);
	}

	function testMalformedPathsAreRefused() {
		for (p in ["relative.txt", "/a\\..\\b", "/a\x00.html"])
			Assert.isNull(StaticPathPolicy.resolve(ROOT, p), p);
		Assert.isNull(StaticPathPolicy.resolve(null, "/x"));
		Assert.isNull(StaticPathPolicy.resolve(ROOT, null));
	}

	function testRelativeRootIsAnchoredAtCwd() {
		Assert.equals("/home/run/public/x.css", StaticPathPolicy.resolve("public", "/x.css", "/home/run"));
		Assert.equals("/home/run/x.css", StaticPathPolicy.resolve(".", "/x.css", "/home/run"));
		Assert.isNull(StaticPathPolicy.resolve(".", "/../etc/passwd", "/home/run"));
	}
}
