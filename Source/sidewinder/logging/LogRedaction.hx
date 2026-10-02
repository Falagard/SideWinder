package sidewinder.logging;

/**
 * Credential masking for anything that logs request/response headers.
 *
 * CustomSocketDriver used to log every request's full header set at INFO - so session cookies,
 * bearer tokens, API/project keys and webhook signatures landed in every log sink
 * (console, files, SqliteLogProvider, Seq). Header dumps are now DEBUG-only and always pass
 * through here first.
 */
class LogRedaction {
	public static final SENSITIVE_HEADERS:Array<String> = [
		"cookie", "set-cookie", "authorization", "proxy-authorization", "x-api-key", "x-project-key",
		"x-auth-token", "x-csrf-token", "x-xsrf-token", "stripe-signature", "x-hub-signature", "x-hub-signature-256"
	];

	public static inline var MASK = "[redacted]";

	public static function isSensitiveHeader(name:String):Bool {
		return name != null && SENSITIVE_HEADERS.indexOf(name.toLowerCase()) >= 0;
	}

	/** "Name: value, Name: value" with sensitive values masked, in the map's iteration order. */
	public static function headerSummary(headers:Map<String, String>):String {
		if (headers == null) return "";
		var parts = [];
		for (k in headers.keys()) parts.push(k + ": " + (isSensitiveHeader(k) ? MASK : headers.get(k)));
		return parts.join(", ");
	}

	/** A raw "Name: value" header block (one header per line); sensitive values masked. */
	public static function rawHeaderBlock(raw:String):String {
		if (raw == null) return "";
		var lines = raw.split("\n");
		for (i in 0...lines.length) {
			var line = lines[i];
			var colon = line.indexOf(":");
			if (colon > 0 && isSensitiveHeader(StringTools.trim(line.substr(0, colon))))
				lines[i] = line.substr(0, colon + 1) + " " + MASK + (StringTools.endsWith(line, "\r") ? "\r" : "");
		}
		return lines.join("\n");
	}
}
