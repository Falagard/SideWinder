package sidewinder;

import sidewinder.AutoClientAsync;
import haxe.Json;

/**
 * Example desktop application demonstrating cookie persistence.
 * Shows how to:
 * 1. Initialize persistent cookies on app startup
 * 2. Use cookies with API clients
 * 3. Restore authentication across app restarts
 * 4. Handle cookie lifecycle
 */
class DesktopAppExample {
	private var cookieJar:PersistentCookieJar;
	private var client:AutoClientAsync;
	private var isAuthenticated:Bool = false;
	
	public function new() {
		HybridLogger.info("Initializing desktop application with persistent cookies");
		
		// Initialize persistent cookie storage
		// This will load existing cookies from disk if they exist
		initializeCookies();
	}
	
	/**
	 * Initialize persistent cookies for the desktop app.
	 * This should be called once at app startup.
	 */
	private function initializeCookies():Void {
		// Create persistent cookie jar
		// By default stores in ~/.sidewinder/cookies.json
		cookieJar = new PersistentCookieJar();
		
		// Set as global for all auto-generated clients
		AutoClientAsync.globalCookieJar = cookieJar;
		
		var existingCookies = cookieJar.getAllCookies();
		HybridLogger.info('Loaded ${existingCookies.length} cookies from persistent storage');
		
		// Log cookie info (without sensitive values)
		for (cookie in existingCookies) {
			HybridLogger.debug('Cookie: ${cookie.name} (domain: ${cookie.domain}, path: ${cookie.path})');
		}
		
		// Check if we have active authentication
		checkAuthenticationStatus();
	}
	
	/**
	 * Check if we have valid authentication cookies from previous session.
	 */
	private function checkAuthenticationStatus():Void {
		var cookies = cookieJar.getAllCookies();
		
		// Look for auth-related cookies
		for (cookie in cookies) {
			if (StringTools.startsWith(cookie.name.toLowerCase(), "session") ||
				StringTools.startsWith(cookie.name.toLowerCase(), "auth") ||
				StringTools.startsWith(cookie.name.toLowerCase(), "token")) {
				isAuthenticated = true;
				HybridLogger.info('Found authentication cookie from previous session: ${cookie.name}');
				break;
			}
		}
		
		if (isAuthenticated) {
			HybridLogger.info("User appears to be authenticated from previous session");
		} else {
			HybridLogger.info("No previous authentication found - user needs to login");
		}
	}
	
	/**
	 * Example login flow that uses cookies for session management.
	 */
	public function login(username:String, password:String, onSuccess:Bool->Void, ?onError:Dynamic->Void):Void {
		HybridLogger.info('Attempting login for user: $username');
		
		// Example: Make login request to API
		// The server will set cookies via Set-Cookie headers
		// These cookies are automatically parsed and stored in the persistent jar
		
		var http = new haxe.Http("https://api.example.com/login");
		http.setHeader("Content-Type", "application/json");
		
		var body = Json.stringify({
			username: username,
			password: password
		});
		
		http.onData = function(response:String) {
			try {
				var result = Json.parse(response);
				if (result.success) {
					isAuthenticated = true;
					HybridLogger.info("Login successful");
					onSuccess(true);
				} else {
					HybridLogger.warn("Login failed: " + result.error);
					onSuccess(false);
				}
			} catch (e:Dynamic) {
				HybridLogger.error("Failed to parselogin response: " + e);
				if (onError != null) onError(e);
			}
		};
		
		http.onError = function(error:String) {
			HybridLogger.error("Login error: " + error);
			if (onError != null) onError(error);
		};
		
		try {
			http.setPostData(body);
			http.request(true);
		} catch (e:Dynamic) {
			HybridLogger.error("Failed to send login request: " + e);
			if (onError != null) onError(e);
		}
	}
	
	/**
	 * Check current authentication status with the server.
	 * Uses cookies if still valid.
	 */
	public function verifySession(onSuccess:Bool->Void, ?onError:Dynamic->Void):Void {
		HybridLogger.info("Verifying session with server");
		
		var http = new haxe.Http("https://api.example.com/me");
		
		// Auto-add cookies for this domain
		var cookieHeader = cookieJar.getCookieHeader("https://api.example.com/me");
		if (cookieHeader != "") {
			http.setHeader("Cookie", cookieHeader);
		}
		
		http.onData = function(response:String) {
			try {
				var result = Json.parse(response);
				isAuthenticated = result.authenticated ?? false;
				HybridLogger.info('Session verification: authenticated=${isAuthenticated}');
				onSuccess(isAuthenticated);
			} catch (e:Dynamic) {
				HybridLogger.error("Failed to verify session: " + e);
				if (onError != null) onError(e);
			}
		};
		
		http.onError = function(error:String) {
			HybridLogger.warn("Session verification failed: " + error);
			isAuthenticated = false;
			onSuccess(false);
		};
		
		http.request(false);
	}
	
	/**
	 * Logout and clear authentication cookies.
	 */
	public function logout(onComplete:Void->Void):Void {
		HybridLogger.info("Logging out");
		
		var http = new haxe.Http("https://api.example.com/logout");
		
		// Send logout request with cookies
		var cookieHeader = cookieJar.getCookieHeader("https://api.example.com/logout");
		if (cookieHeader != "") {
			http.setHeader("Cookie", cookieHeader);
		}
		
		http.onData = function(_:String) {
			// Clear local cookies after logout request completes
			cookieJar.clear();
			isAuthenticated = false;
			HybridLogger.info("Logout complete - cookies cleared");
			if (onComplete != null) onComplete();
		};
		
		http.onError = function(error:String) {
			HybridLogger.warn("Logout request failed: " + error);
			// Still clear local cookies even if server logout fails
			cookieJar.clear();
			isAuthenticated = false;
			if (onComplete != null) onComplete();
		};
		
		try {
			http.request(true);
		} catch (e:Dynamic) {
			// If we can't even send the logout, still clear local cookies
			cookieJar.clear();
			isAuthenticated = false;
			HybridLogger.error("Failed to send logout request: " + e);
			if (onComplete != null) onComplete();
		}
	}
	
	/**
	 * Make an authenticated API request.
	 * Cookies are automatically included if stored.
	 */
	public function makeAuthenticatedRequest(url:String, onSuccess:String->Void, ?onError:Dynamic->Void):Void {
		HybridLogger.debug('Making authenticated request to: $url');
		
		if (!isAuthenticated) {
			var error = "Not authenticated - please login first";
			HybridLogger.warn(error);
			if (onError != null) onError(error);
			return;
		}
		
		var http = new haxe.Http(url);
		
		// Automatically add stored cookies
		var cookieHeader = cookieJar.getCookieHeader(url);
		if (cookieHeader != "") {
			http.setHeader("Cookie", cookieHeader);
			HybridLogger.debug('Adding ${cookieHeader.split(";").length} cookies to request');
		}
		
		http.onData = function(response:String) {
			try {
				HybridLogger.debug("Request successful");
				onSuccess(response);
			} catch (e:Dynamic) {
				HybridLogger.error("Failed to process response: " + e);
				if (onError != null) onError(e);
			}
		};
		
		http.onError = function(error:String) {
			// If we get a 401, clear cookies as they're invalid
			HybridLogger.error("Request failed: " + error);
			if (StringTools.contains(error, "401")) {
				HybridLogger.warn("Got 401 - clearing invalid cookies");
				cookieJar.clear();
				isAuthenticated = false;
			}
			if (onError != null) onError(error);
		};
		
		http.request(false);
	}
	
	/**
	 * Export cookies for backup or migration.
	 */
	public function exportCookies(filename:String):Void {
		var json = cookieJar.exportCookies();
		sys.io.File.saveContent(filename, json);
		HybridLogger.info('Exported cookies to: $filename');
	}
	
	/**
	 * Import cookies from backup.
	 */
	public function importCookies(filename:String):Void {
		try {
			var json = sys.io.File.getContent(filename);
			cookieJar.importCookies(json);
			HybridLogger.info('Imported cookies from: $filename');
		} catch (e:Dynamic) {
			HybridLogger.error('Failed to import cookies: $e');
		}
	}
	
	/**
	 * Get current authentication state.
	 */
	public function isLoggedIn():Bool {
		return isAuthenticated;
	}
	
	/**
	 * Get all stored cookies (for debugging).
	 */
	public function getCookies():Array<Cookie> {
		return cookieJar.getAllCookies();
	}
	
	/**
	 * Get cookie storage path.
	 */
	public function getCookieStoragePath():String {
		return cookieJar.getStoragePath();
	}
}

/**
 * Example of using desktop app with proper error handling.
 */
class DesktopAppExampleUsage {
	public static function main() {
		HybridLogger.init(HybridLogger.LogLevel.DEBUG);
		
		var app = new DesktopAppExample();
		
		// Check if already authenticated
		if (app.isLoggedIn()) {
			HybridLogger.info("User is logged in from previous session");
			verifyAndContinue(app);
		} else {
			HybridLogger.info("User needs to login");
			performLogin(app);
		}
	}
	
	private static function verifyAndContinue(app:DesktopAppExample):Void {
		app.verifySession(
			function(isValid:Bool) {
				if (isValid) {
					HybridLogger.info("Session is still valid");
					makeRequest(app);
				} else {
					HybridLogger.info("Session expired - need to login again");
					performLogin(app);
				}
			},
			function(error:Dynamic) {
				HybridLogger.error("Failed to verify session: " + error);
				performLogin(app);
			}
		);
	}
	
	private static function performLogin(app:DesktopAppExample):Void {
		app.login("username", "password",
			function(success:Bool) {
				if (success) {
					makeRequest(app);
				} else {
					HybridLogger.info("Login failed");
				}
			},
			function(error:Dynamic) {
				HybridLogger.error("Login error: " + error);
			}
		);
	}
	
	private static function makeRequest(app:DesktopAppExample):Void {
		app.makeAuthenticatedRequest(
			"https://api.example.com/data",
			function(response:String) {
				HybridLogger.info("Got data: " + response.substr(0, 100));
			},
			function(error:Dynamic) {
				HybridLogger.error("Request failed: " + error);
			}
		);
	}
}
