package sidewinder;

import haxe.Json;
import sys.io.File;
import sys.FileSystem;

/**
 * Persistent cookie storage for desktop applications.
 * Extends CookieJar with automatic file persistence.
 * Cookies are saved to JSON files automatically on every change.
 */
class PersistentCookieJar extends CookieJar {
	private var storagePath:String;
	private var cookieFile:String;
	
	/**
	 * Create a persistent cookie jar.
	 * @param storagePath Directory to store cookies in (defaults to user's home/.sidewinder)
	 */
	public function new(?storagePath:String) {
		super();
		
		if (storagePath == null) {
			// Use standard application data directory
			var homeDir = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".";
			storagePath = homeDir + "/.sidewinder";
		}
		
		this.storagePath = storagePath;
		this.cookieFile = storagePath + "/cookies.json";
		
		// Create directory if it doesn't exist
		if (!FileSystem.exists(storagePath)) {
			FileSystem.createDirectory(storagePath);
		}
		
		// Load existing cookies from file
		loadCookies();
	}
	
	/**
	 * Override setCookie to persist changes.
	 */
	override public function setCookie(setCookieHeader:String, url:String):Void {
		super.setCookie(setCookieHeader, url);
		saveCookies();
	}
	
	/**
	 * Override clear to persist changes.
	 */
	override public function clear():Void {
		super.clear();
		saveCookies();
	}
	
	/**
	 * Load cookies from the persisted JSON file.
	 */
	private function loadCookies():Void {
		try {
			if (FileSystem.exists(cookieFile)) {
				var content = File.getContent(cookieFile);
				var parsed:Dynamic = Json.parse(content);
				
				if (parsed != null && parsed.cookies != null) {
					var cookiesData:Array<Dynamic> = parsed.cookies;
					for (cookieData in cookiesData) {
						try {
							var cookie = new Cookie(cookieData.name, cookieData.value);
							if (cookieData.domain != null) cookie.domain = cookieData.domain;
							if (cookieData.path != null) cookie.path = cookieData.path;
							if (cookieData.expires != null) cookie.expires = cookieData.expires;
							if (cookieData.maxAge != null) cookie.maxAge = cookieData.maxAge;
							if (cookieData.secure != null) cookie.secure = cookieData.secure;
							if (cookieData.httpOnly != null) cookie.httpOnly = cookieData.httpOnly;
							if (cookieData.sameSite != null) cookie.sameSite = cookieData.sameSite;
							if (cookieData.createdAt != null) cookie.createdAt = cookieData.createdAt;
							
							// Only add if not expired
							if (!isExpired(cookie)) {
								cookies.push(cookie);
							}
						} catch (e:Dynamic) {
							HybridLogger.warn('Failed to load cookie: ${e}');
						}
					}
				}
				
				HybridLogger.info('Loaded ${cookies.length} cookies from ${cookieFile}');
			}
		} catch (e:Dynamic) {
			HybridLogger.warn('Failed to load cookies: ${e}');
		}
	}
	
	/**
	 * Save cookies to the persisted JSON file.
	 */
	private function saveCookies():Void {
		try {
			// Clean up expired cookies before saving
			cookies = cookies.filter(function(c) return !isExpired(c));
			
			// Serialize cookies
			var cookiesData = [];
			for (cookie in cookies) {
				cookiesData.push({
					name: cookie.name,
					value: cookie.value,
					domain: cookie.domain,
					path: cookie.path,
					expires: cookie.expires,
					maxAge: cookie.maxAge,
					secure: cookie.secure,
					httpOnly: cookie.httpOnly,
					sameSite: cookie.sameSite,
					createdAt: cookie.createdAt
				});
			}
			
			var data = {
				cookies: cookiesData,
				savedAt: Date.now().toString()
			};
			
			File.saveContent(cookieFile, Json.stringify(data));
			HybridLogger.debug('Saved ${cookies.length} cookies to ${cookieFile}');
		} catch (e:Dynamic) {
			HybridLogger.error('Failed to save cookies: ${e}');
		}
	}
	
	/**
	 * Get the path where cookies are stored.
	 */
	public function getStoragePath():String {
		return storagePath;
	}
	
	/**
	 * Clear all cookies and delete the cookie file.
	 */
	public function clearAndDeleteFile():Void {
		clear();
		try {
			if (FileSystem.exists(cookieFile)) {
				FileSystem.deleteFile(cookieFile);
				HybridLogger.info('Deleted cookie file: ${cookieFile}');
			}
		} catch (e:Dynamic) {
			HybridLogger.warn('Failed to delete cookie file: ${e}');
		}
	}
	
	/**
	 * Export cookies for backup.
	 */
	public function exportCookies():String {
		var cookiesData = [];
		for (cookie in getAllCookies()) {
			cookiesData.push({
				name: cookie.name,
				value: cookie.value,
				domain: cookie.domain,
				path: cookie.path,
				expires: cookie.expires,
				maxAge: cookie.maxAge,
				secure: cookie.secure,
				httpOnly: cookie.httpOnly,
				sameSite: cookie.sameSite,
				createdAt: cookie.createdAt
			});
		}
		
		return Json.stringify({
			version: "1.0",
			cookieCount: cookiesData.length,
			exportedAt: Date.now().toString(),
			cookies: cookiesData
		});
	}
	
	/**
	 * Import cookies from exported JSON.
	 */
	public function importCookies(jsonData:String):Void {
		try {
			var parsed:Dynamic = Json.parse(jsonData);
			if (parsed != null && parsed.cookies != null) {
				var cookiesData:Array<Dynamic> = parsed.cookies;
				for (cookieData in cookiesData) {
					try {
						var cookie = new Cookie(cookieData.name, cookieData.value);
						if (cookieData.domain != null) cookie.domain = cookieData.domain;
						if (cookieData.path != null) cookie.path = cookieData.path;
						if (cookieData.expires != null) cookie.expires = cookieData.expires;
						if (cookieData.maxAge != null) cookie.maxAge = cookieData.maxAge;
						if (cookieData.secure != null) cookie.secure = cookieData.secure;
						if (cookieData.httpOnly != null) cookie.httpOnly = cookieData.httpOnly;
						if (cookieData.sameSite != null) cookie.sameSite = cookieData.sameSite;
						if (cookieData.createdAt != null) cookie.createdAt = cookieData.createdAt;
						
						// Only add if not expired
						if (!isExpired(cookie)) {
							cookies.push(cookie);
						}
					} catch (e:Dynamic) {
						HybridLogger.warn('Failed to import cookie: ${e}');
					}
				}
				saveCookies();
				HybridLogger.info('Imported ${cookiesData.length} cookies');
			}
		} catch (e:Dynamic) {
			HybridLogger.error('Failed to import cookies: ${e}');
		}
	}
}
