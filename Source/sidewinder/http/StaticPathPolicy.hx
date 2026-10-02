package sidewinder.http;

import haxe.io.Path;

/**
 * Maps a request path to a file under a static root, or refuses.
 *
 * HxWellAdapter's unmatched-request fallback used to do
 * `Path.join([baseDir, requestPath])` with no further checks. `Path.join` normalizes `..`,
 * and hxwell URL-decodes the request path first, so `GET /../../secret.txt` and
 * `GET /%2e%2e/%2e%2e/secret.txt` both read files OUTSIDE the static root. It also served
 * whatever sat inside the root - StackServerSDK passes the application DATA directory, so
 * `GET /project.db` downloaded the application database.
 *
 * Rules:
 *  - the resolved file must be inside the root (checked after normalization);
 *  - no `..` segment, no NUL, no backslash;
 *  - no dot-files or dot-directories (`.env`, `.git/...`), except `/.well-known/...`;
 *  - never database, secret or binary files (see DENIED_EXTENSIONS), even inside the root.
 *
 * Pure (no I/O) so the core test suite covers it: tests/sidewinder/http/StaticPathPolicyTest.hx.
 */
class StaticPathPolicy {
	public static final DENIED_EXTENSIONS:Array<String> = [
		"db", "db-wal", "db-shm", "db-journal", "sqlite", "sqlite3", "sqlite-wal", "sqlite-shm",
		"env", "pem", "key", "p12", "pfx", "jks", "log",
		"hl", "hdll", "ndll", "dll", "so", "dylib", "exe"
	];

	/**
	 * @param baseDir      static root; relative roots are resolved against `cwd`
	 * @param requestPath  decoded request path, e.g. "/css/site.css?v=1"
	 * @return absolute file path to serve, or null to refuse
	 */
	public static function resolve(baseDir:String, requestPath:String, ?cwd:String):Null<String> {
		if (baseDir == null || requestPath == null) return null;
		var pathOnly = requestPath.split("?")[0].split("#")[0];
		if (pathOnly.indexOf("\x00") >= 0 || pathOnly.indexOf("\\") >= 0) return null;
		if (pathOnly == "" || pathOnly == "/") pathOnly = "/index.html";
		if (StringTools.startsWith(pathOnly, "/static/")) pathOnly = pathOnly.substr("/static".length);
		if (pathOnly.charAt(0) != "/") return null;

		var segments = pathOnly.substr(1).split("/");
		for (i in 0...segments.length) {
			var seg = segments[i];
			if (seg == "..") return null;
			if (seg.length > 0 && seg.charAt(0) == "." && !(i == 0 && seg == ".well-known")) return null;
		}

		var ext = Path.extension(pathOnly).toLowerCase();
		if (DENIED_EXTENSIONS.indexOf(ext) >= 0) return null;

		var root = Path.isAbsolute(baseDir) ? baseDir : Path.join([cwd != null ? cwd : Sys.getCwd(), baseDir]);
		root = Path.removeTrailingSlashes(Path.normalize(root));
		var full = Path.normalize(Path.join([root, pathOnly.substr(1)]));
		if (!StringTools.startsWith(full, root + "/")) return null;
		return full;
	}
}
