package sidewinder;

import sidewinder.AutoClientAsync;
import haxe.Json;

/**
 * Test suite and examples for PersistentCookieJar functionality.
 * Run these tests to verify persistence behavior.
 */
class PersistentCookieJarTests {
	
	/**
	 * Test 1: Basic persistence - save and load
	 */
	public static function testBasicPersistence():Void {
		HybridLogger.info("=== Test 1: Basic Persistence ===");
		
		// Create temp directory for test
		var testDir = "./test_cookies_" + Std.string(Date.now().getTime());
		
		try {
			// Create persistent jar and add a cookie
			var jar1 = new PersistentCookieJar(testDir);
			jar1.setCookie("session_id=abc123; Domain=example.com; Path=/", "https://example.com/");
			
			var cookies1 = jar1.getAllCookies();
			HybridLogger.info('Jar 1 added ${cookies1.length} cookies');
			
			// Create a new jar pointing to same location - should load cookies
			var jar2 = new PersistentCookieJar(testDir);
			var cookies2 = jar2.getAllCookies();
			HybridLogger.info('Jar 2 loaded ${cookies2.length} cookies');
			
			// Verify
			if (cookies2.length == 1 && cookies2[0].name == "session_id") {
				HybridLogger.info("✓ Test 1 PASSED: Cookies persisted and loaded");
			} else {
				HybridLogger.error("✗ Test 1 FAILED: Cookie not persisted correctly");
			}
			
			// Cleanup
			cleanupTestDir(testDir);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 1 ERROR: " + e);
		}
	}
	
	/**
	 * Test 2: Expired cookies are not loaded
	 */
	public static function testExpiredCookieCleanup():Void {
		HybridLogger.info("=== Test 2: Expired Cookie Cleanup ===");
		
		var testDir = "./test_cookies_" + Std.string(Date.now().getTime());
		
		try {
			var jar = new PersistentCookieJar(testDir);
			
			// Add a cookie with very short maxAge
			jar.setCookie("temp=value; Max-Age=1", "https://example.com/");
			var beforeWait = jar.getAllCookies().length;
			HybridLogger.info('Added ${beforeWait} temporary cookie(s)');
			
			// Wait for cookie to expire
			Sys.sleep(1.1);
			
			// Create a new jar - should not load expired cookie
			var jar2 = new PersistentCookieJar(testDir);
			var afterLoad = jar2.getAllCookies().length;
			
			if (afterLoad == 0) {
				HybridLogger.info("✓ Test 2 PASSED: Expired cookies not loaded");
			} else {
				HybridLogger.error("✗ Test 2 FAILED: Expired cookie was loaded");
			}
			
			cleanupTestDir(testDir);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 2 ERROR: " + e);
		}
	}
	
	/**
	 * Test 3: Multiple cookies with different domains
	 */
	public static function testMultipleDomains():Void {
		HybridLogger.info("=== Test 3: Multiple Domains ===");
		
		var testDir = "./test_cookies_" + Std.string(Date.now().getTime());
		
		try {
			var jar1 = new PersistentCookieJar(testDir);
			
			// Add cookies for different domains
			jar1.setCookie("api_session=123; Domain=api.example.com; Path=/", "https://api.example.com/");
			jar1.setCookie("auth_token=abc; Domain=auth.example.com; Path=/", "https://auth.example.com/");
			jar1.setCookie("user_pref=dark; Domain=example.com; Path=/", "https://example.com/");
			
			HybridLogger.info('Added ${jar1.getAllCookies().length} cookies across 3 domains');
			
			// Load with new jar
			var jar2 = new PersistentCookieJar(testDir);
			var all = jar2.getAllCookies();
			
			// Check domain matching
			var apiCookies = jar2.getCookieHeader("https://api.example.com/");
			var authCookies = jar2.getCookieHeader("https://auth.example.com/");
			var mainCookies = jar2.getCookieHeader("https://example.com/");
			
			HybridLogger.info('API cookies: $apiCookies');
			HybridLogger.info('Auth cookies: $authCookies');
			HybridLogger.info('Main cookies: $mainCookies');
			
			if (all.length == 3 && 
				apiCookies.length > 0 && 
				authCookies.length > 0 &&
				mainCookies.length > 0) {
				HybridLogger.info("✓ Test 3 PASSED: Multiple domains work correctly");
			} else {
				HybridLogger.error("✗ Test 3 FAILED: Domain handling incorrect");
			}
			
			cleanupTestDir(testDir);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 3 ERROR: " + e);
		}
	}
	
	/**
	 * Test 4: Import/Export functionality
	 */
	public static function testImportExport():Void {
		HybridLogger.info("=== Test 4: Import/Export ===");
		
		var testDir1 = "./test_cookies_" + Std.string(Date.now().getTime());
		var testDir2 = "./test_cookies_" + Std.string(Date.now().getTime() + 1);
		
		try {
			// Create jar1 with some cookies
			var jar1 = new PersistentCookieJar(testDir1);
			jar1.setCookie("test=value1; Domain=example.com", "https://example.com/");
			jar1.setCookie("test2=value2; Domain=example.com", "https://example.com/");
			
			// Export
			var exported = jar1.exportCookies();
			HybridLogger.info('Exported cookies: ${exported.length} bytes');
			
			// Import into new jar
			var jar2 = new PersistentCookieJar(testDir2);
			jar2.importCookies(exported);
			
			var imported = jar2.getAllCookies();
			if (imported.length == 2) {
				HybridLogger.info("✓ Test 4 PASSED: Import/Export works correctly");
			} else {
				HybridLogger.error("✗ Test 4 FAILED: Import/Export count mismatch");
			}
			
			cleanupTestDir(testDir1);
			cleanupTestDir(testDir2);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 4 ERROR: " + e);
		}
	}
	
	/**
	 * Test 5: Clear and delete file
	 */
	public static function testClearAndDelete():Void {
		HybridLogger.info("=== Test 5: Clear and Delete ===");
		
		var testDir = "./test_cookies_" + Std.string(Date.now().getTime());
		var cookieFile = testDir + "/cookies.json";
		
		try {
			// Create jar with cookies
			var jar = new PersistentCookieJar(testDir);
			jar.setCookie("test=value; Domain=example.com", "https://example.com/");
			
			if (sys.FileSystem.exists(cookieFile)) {
				HybridLogger.info("Cookie file created successfully");
			}
			
			// Clear and delete
			jar.clearAndDeleteFile();
			
			if (!sys.FileSystem.exists(cookieFile)) {
				HybridLogger.info("✓ Test 5 PASSED: File deleted successfully");
			} else {
				HybridLogger.error("✗ Test 5 FAILED: File still exists after delete");
			}
			
			cleanupTestDir(testDir);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 5 ERROR: " + e);
		}
	}
	
	/**
	 * Test 6: Cookie matching for auto-generated clients
	 */
	public static function testCookieMatching():Void {
		HybridLogger.info("=== Test 6: Cookie Matching ===");
		
		var testDir = "./test_cookies_" + Std.string(Date.now().getTime());
		
		try {
			var jar = new PersistentCookieJar(testDir);
			
			// Add cookies with different attributes
			jar.setCookie("public=value; Domain=example.com; Path=/", "https://example.com/");
			jar.setCookie("secure_only=secret; Domain=api.example.com; Path=/api/; Secure", "https://api.example.com/api/");
			jar.setCookie("public_sub=value; Domain=.example.com; Path=/", "https://subdomain.example.com/");
			
			// Test matching
			var test1 = jar.getCookieHeader("https://example.com/path");
			var test2 = jar.getCookieHeader("https://api.example.com/api/endpoint");
			var test3 = jar.getCookieHeader("https://subdomain.example.com/path");
			var test4 = jar.getCookieHeader("http://api.example.com/api/"); // Not secure, shouldn't match secure_only
			
			HybridLogger.info('example.com: $test1');
			HybridLogger.info('api.example.com (HTTPS): $test2');
			HybridLogger.info('subdomain.example.com: $test3');
			HybridLogger.info('api.example.com (HTTP): $test4');
			
			if (test1.length > 0 && test2.length > 0 && test3.length > 0) {
				HybridLogger.info("✓ Test 6 PASSED: Cookie matching works correctly");
			} else {
				HybridLogger.error("✗ Test 6 FAILED: Cookie matching incorrect");
			}
			
			cleanupTestDir(testDir);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 6 ERROR: " + e);
		}
	}
	
	/**
	 * Test 7: Global cookie jar integration with AutoClientAsync
	 */
	public static function testGlobalCookieJar():Void {
		HybridLogger.info("=== Test 7: Global Cookie Jar ===");
		
		var testDir = "./test_cookies_" + Std.string(Date.now().getTime());
		
		try {
			// Set persistent jar as global
			var persistentJar = new PersistentCookieJar(testDir);
			AutoClientAsync.globalCookieJar = persistentJar;
			
			// Add cookies via global jar
			AutoClientAsync.globalCookieJar.setCookie("global=test; Domain=example.com", "https://example.com/");
			
			// Verify it's the same instance
			var cookies = AutoClientAsync.globalCookieJar.getAllCookies();
			
			if (cookies.length == 1 && AutoClientAsync.globalCookieJar == persistentJar) {
				HybridLogger.info("✓ Test 7 PASSED: Global cookie jar integration works");
			} else {
				HybridLogger.error("✗ Test 7 FAILED: Global cookie jar not set correctly");
			}
			
			cleanupTestDir(testDir);
		} catch (e:Dynamic) {
			HybridLogger.error("✗ Test 7 ERROR: " + e);
		}
	}
	
	/**
	 * Run all tests
	 */
	public static function runAllTests():Void {
		HybridLogger.init(HybridLogger.LogLevel.INFO);
		
		HybridLogger.info("Starting PersistentCookieJar Test Suite");
		HybridLogger.info("=====================================");
		
		testBasicPersistence();
		testExpiredCookieCleanup();
		testMultipleDomains();
		testImportExport();
		testClearAndDelete();
		testCookieMatching();
		testGlobalCookieJar();
		
		HybridLogger.info("=====================================");
		HybridLogger.info("Test Suite Complete");
	}
	
	// Helper function
	private static function cleanupTestDir(dir:String):Void {
		try {
			if (sys.FileSystem.exists(dir)) {
				var cookieFile = dir + "/cookies.json";
				if (sys.FileSystem.exists(cookieFile)) {
					sys.FileSystem.deleteFile(cookieFile);
				}
				sys.FileSystem.deleteDirectory(dir);
			}
		} catch (e:Dynamic) {
			HybridLogger.warn('Failed to cleanup test directory: $dir');
		}
	}
}

/**
 * Manual test scenarios for exploring persistence behavior
 */
class PersistentCookieJarManualTest {
	public static function main():Void {
		HybridLogger.init(HybridLogger.LogLevel.DEBUG);
		
		trace("=== Manual Cookie Persistence Test ===");
		
		// Test 1: Create cookies and verify file
		trace("\n1. Creating cookies...");
		var jar = new PersistentCookieJar();
		jar.setCookie("session=abc123; Max-Age=3600; Secure; HttpOnly; SameSite=Lax", "https://api.example.com/");
		jar.setCookie("pref=dark_mode", "https://example.com/");
		
		trace('Cookies added: ${jar.getAllCookies().length}');
		trace('Storage path: ${jar.getStoragePath()}');
		
		// Test 2: Simulate app restart
		trace("\n2. Simulating app restart...");
		var jar2 = new PersistentCookieJar();
		trace('Cookies loaded: ${jar2.getAllCookies().length}');
		
		for (cookie in jar2.getAllCookies()) {
			trace('  - ${cookie.name}=${cookie.value} (domain: ${cookie.domain})');
		}
		
		// Test 3: Export/Import
		trace("\n3. Testing export/import...");
		var exported = jar2.exportCookies();
		trace('Exported data size: ${exported.length} bytes');
		
		var jar3 = new PersistentCookieJar("./backup_test");
		jar3.importCookies(exported);
		trace('Imported ${jar3.getAllCookies().length} cookies');
		
		// Test 4: Verify cookie matching
		trace("\n3. Verifying cookie matching...");
		var header = jar2.getCookieHeader("https://api.example.com/auth");
		trace('Cookies for api.example.com: $header');
		
		var header2 = jar2.getCookieHeader("https://example.com/settings");
		trace('Cookies for example.com: $header2');
		
		trace("\n=== Test Complete ===");
		trace("Check ~/.sidewinder/cookies.json to see persisted cookies");
	}
}
