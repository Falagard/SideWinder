package sidewinder;

import haxe.ds.StringMap;

/**
 * Cookie storage with domain and path support.
 * Handles Set-Cookie header parsing and Cookie header generation.
 */
class CookieJar {
	private var cookies:Array<Cookie> = [];

	public function new() {}

	/**
	 * Parse and store cookies from Set-Cookie header(s).
	 * @param setCookieHeader The value of a Set-Cookie header
	 * @param url The URL of the request (used to extract domain/path)
	 */
	public function setCookie(setCookieHeader:String, url:String):Void {
		if (setCookieHeader == null || setCookieHeader == "") return;
		
		var parts = setCookieHeader.split(";");
		if (parts.length == 0) return;
		
		// First part is name=value
		var nameValue = parts[0].split("=");
		if (nameValue.length < 2) return;
		
		var name = StringTools.trim(nameValue[0]);
		var value = StringTools.trim(nameValue[1]);
		
		var cookie = new Cookie(name, value);
		
		// Extract domain and path from URL
		var urlParts = extractUrlParts(url);
		cookie.domain = urlParts.domain;
		cookie.path = urlParts.path;
		
		// Parse attributes
		for (i in 1...parts.length) {
			var attr = StringTools.trim(parts[i]);
			var attrParts = attr.split("=");
			var attrName = StringTools.trim(attrParts[0]).toLowerCase();
			var attrValue = attrParts.length > 1 ? StringTools.trim(attrParts[1]) : "";
			
			switch (attrName) {
				case "domain":
					cookie.domain = attrValue;
				case "path":
					cookie.path = attrValue;
				case "expires":
					cookie.expires = attrValue;
				case "max-age":
					var maxAge = Std.parseInt(attrValue);
					if (maxAge != null) {
						cookie.maxAge = maxAge;
					}
				case "secure":
					cookie.secure = true;
				case "httponly":
					cookie.httpOnly = true;
				case "samesite":
					cookie.sameSite = attrValue;
			}
		}
		
		// Remove any existing cookie with same name/domain/path
		cookies = cookies.filter(function(c) {
			return !(c.name == name && c.domain == cookie.domain && c.path == cookie.path);
		});
		
		// Add new cookie if not expired
		if (!isExpired(cookie)) {
			cookies.push(cookie);
		}
	}
	
	/**
	 * Get all cookies that match the given URL as a Cookie header string.
	 * @param url The URL to match cookies against
	 * @return Cookie header value (e.g., "name1=value1; name2=value2")
	 */
	public function getCookieHeader(url:String):String {
		var urlParts = extractUrlParts(url);
		var matchingCookies = [];
		
		// Clean up expired cookies
		cookies = cookies.filter(function(c) return !isExpired(c));
		
		for (cookie in cookies) {
			if (matches(cookie, urlParts)) {
				matchingCookies.push(cookie.name + "=" + cookie.value);
			}
		}
		
		return matchingCookies.join("; ");
	}
	
	/**
	 * Clear all cookies.
	 */
	public function clear():Void {
		cookies = [];
	}
	
	/**
	 * Get all stored cookies (for debugging).
	 */
	public function getAllCookies():Array<Cookie> {
		return cookies.copy();
	}
	
	// Helper methods
	
	private function extractUrlParts(url:String):{domain:String, path:String, isSecure:Bool} {
		var isSecure = StringTools.startsWith(url, "https://");
		var withoutProtocol = url;
		
		if (StringTools.startsWith(url, "http://")) {
			withoutProtocol = url.substr(7);
		} else if (StringTools.startsWith(url, "https://")) {
			withoutProtocol = url.substr(8);
		}
		
		var slashPos = withoutProtocol.indexOf("/");
		var domain = slashPos == -1 ? withoutProtocol : withoutProtocol.substr(0, slashPos);
		var path = slashPos == -1 ? "/" : withoutProtocol.substr(slashPos);
		
		// Remove port from domain if present
		var colonPos = domain.indexOf(":");
		if (colonPos != -1) {
			domain = domain.substr(0, colonPos);
		}
		
		// Remove query string and fragment from path
		var queryPos = path.indexOf("?");
		if (queryPos != -1) {
			path = path.substr(0, queryPos);
		}
		var fragmentPos = path.indexOf("#");
		if (fragmentPos != -1) {
			path = path.substr(0, fragmentPos);
		}
		
		// Normalize path to directory
		if (path == "") path = "/";
		var lastSlash = path.lastIndexOf("/");
		if (lastSlash > 0) {
			path = path.substr(0, lastSlash + 1);
		}
		
		return {domain: domain, path: path, isSecure: isSecure};
	}
	
	private function matches(cookie:Cookie, urlParts:{domain:String, path:String, isSecure:Bool}):Bool {
		// Check secure flag
		if (cookie.secure && !urlParts.isSecure) {
			return false;
		}
		
		// Check domain match
		if (!domainMatches(cookie.domain, urlParts.domain)) {
			return false;
		}
		
		// Check path match
		if (!pathMatches(cookie.path, urlParts.path)) {
			return false;
		}
		
		return true;
	}
	
	private function domainMatches(cookieDomain:String, requestDomain:String):Bool {
		if (cookieDomain == requestDomain) return true;
		
		// Handle domain prefix (e.g., .example.com matches sub.example.com)
		if (StringTools.startsWith(cookieDomain, ".")) {
			return StringTools.endsWith(requestDomain, cookieDomain) || 
			       requestDomain == cookieDomain.substr(1);
		}
		
		return false;
	}
	
	private function pathMatches(cookiePath:String, requestPath:String):Bool {
		// Cookie path must be a prefix of request path
		return StringTools.startsWith(requestPath, cookiePath);
	}
	
	private function isExpired(cookie:Cookie):Bool {
		var now = Date.now().getTime();
		
		// Check max-age first (takes precedence over expires)
		if (cookie.maxAge != null) {
			var expiryTime = cookie.createdAt + (cookie.maxAge * 1000);
			return now > expiryTime;
		}
		
		// Check expires attribute
		if (cookie.expires != null) {
			try {
				var expiryDate = Date.fromString(cookie.expires);
				return now > expiryDate.getTime();
			} catch (e:Dynamic) {
				// If we can't parse the date, assume not expired
				return false;
			}
		}
		
		// No expiry set - session cookie, never expires
		return false;
	}
}

/**
 * Represents a single HTTP cookie.
 */
class Cookie {
	public var name:String;
	public var value:String;
	public var domain:String;
	public var path:String = "/";
	public var expires:String = null;
	public var maxAge:Null<Int> = null;
	public var secure:Bool = false;
	public var httpOnly:Bool = false;
	public var sameSite:String = null;
	public var createdAt:Float;
	
	public function new(name:String, value:String) {
		this.name = name;
		this.value = value;
		this.createdAt = Date.now().getTime();
	}
	
	public function toString():String {
		return '$name=$value (domain=$domain, path=$path)';
	}
}
