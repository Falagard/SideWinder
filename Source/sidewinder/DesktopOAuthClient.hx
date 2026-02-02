package sidewinder;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.crypto.Base64;
import sys.net.Socket;
import sys.net.Host;

/**
 * Desktop OAuth Client
 * Handles OAuth 2.0 flow for desktop applications using:
 * 1. Local loopback server for callback
 * 2. PKCE for security (no client secret needed)
 * 3. Automatic browser launch
 */
class DesktopOAuthClient {
	private var config:DesktopOAuthConfig;
	private var codeVerifier:String;
	private var codeChallenge:String;
	private var state:String;
	private var callbackServer:LoopbackServer;
	
	public function new(config:DesktopOAuthConfig) {
		this.config = config;
	}

	/**
	 * Start OAuth authorization flow
	 * Returns authorization code or throws error
	 */
	public function authorize():AuthorizationResult {
		// Generate PKCE parameters
		codeVerifier = generateCodeVerifier();
		codeChallenge = generateCodeChallenge(codeVerifier);
		state = generateState();

		// Start local callback server
		var port = config.callbackPort ?? 8080;
		callbackServer = new LoopbackServer(port);
		
		trace('Starting local callback server on port ${port}...');
		
		// Build authorization URL
		var authUrl = buildAuthorizationUrl();
		
		trace('Opening browser to: ${authUrl}');
		
		// Open browser
		openBrowser(authUrl);
		
		// Wait for callback (blocking)
		trace('Waiting for OAuth callback...');
		var callback = callbackServer.waitForCallback(config.timeoutSeconds ?? 300);
		
		// Validate state
		if (callback.state != state) {
			throw "State mismatch - possible CSRF attack";
		}
		
		if (callback.error != null) {
			throw "OAuth error: " + callback.error;
		}
		
		trace('Authorization code received!');
		
		return {
			code: callback.code,
			state: callback.state,
			codeVerifier: codeVerifier
		};
	}

	/**
	 * Exchange authorization code for access token
	 */
	public function exchangeToken(authResult:AuthorizationResult):OAuthTokenResponse {
		var http = new Http(config.tokenEndpoint);
		http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		http.setHeader("Accept", "application/json");

		var params = [
			"grant_type=authorization_code",
			"code=" + StringTools.urlEncode(authResult.code),
			"client_id=" + StringTools.urlEncode(config.clientId),
			"redirect_uri=" + StringTools.urlEncode(config.redirectUri),
			"code_verifier=" + StringTools.urlEncode(authResult.codeVerifier)
		];

		// Only include client secret if provided (not recommended for desktop apps)
		if (config.clientSecret != null) {
			params.push("client_secret=" + StringTools.urlEncode(config.clientSecret));
		}

		var body = params.join("&");
		var result:String = "";
		var error:String = "";

		http.onData = function(data:String) {
			result = data;
		};

		http.onError = function(err:String) {
			error = err;
		};

		try {
			http.setPostData(body);
			http.request(true);
		} catch (e:Dynamic) {
			throw "Failed to exchange token: " + Std.string(e);
		}

		if (error != "") {
			throw "Token exchange error: " + error;
		}

		var parsed:Dynamic = Json.parse(result);

		if (parsed.error != null) {
			throw "OAuth error: " + parsed.error;
		}

		return {
			accessToken: parsed.access_token,
			refreshToken: parsed.refresh_token,
			expiresIn: parsed.expires_in ?? 3600,
			tokenType: parsed.token_type ?? "Bearer",
			scope: parsed.scope
		};
	}

	/**
	 * Complete flow: authorize + exchange token
	 */
	public function authenticate():OAuthTokenResponse {
		var authResult = authorize();
		return exchangeToken(authResult);
	}

	/**
	 * Refresh an access token
	 */
	public function refreshToken(refreshToken:String):OAuthTokenResponse {
		var http = new Http(config.tokenEndpoint);
		http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		http.setHeader("Accept", "application/json");

		var params = [
			"grant_type=refresh_token",
			"refresh_token=" + StringTools.urlEncode(refreshToken),
			"client_id=" + StringTools.urlEncode(config.clientId)
		];

		if (config.clientSecret != null) {
			params.push("client_secret=" + StringTools.urlEncode(config.clientSecret));
		}

		var body = params.join("&");
		var result:String = "";
		var error:String = "";

		http.onData = function(data:String) {
			result = data;
		};

		http.onError = function(err:String) {
			error = err;
		};

		try {
			http.setPostData(body);
			http.request(true);
		} catch (e:Dynamic) {
			throw "Failed to refresh token: " + Std.string(e);
		}

		if (error != "") {
			throw "Token refresh error: " + error;
		}

		var parsed:Dynamic = Json.parse(result);

		if (parsed.error != null) {
			throw "OAuth error: " + parsed.error;
		}

		return {
			accessToken: parsed.access_token,
			refreshToken: parsed.refresh_token ?? refreshToken,
			expiresIn: parsed.expires_in ?? 3600,
			tokenType: parsed.token_type ?? "Bearer",
			scope: parsed.scope
		};
	}

	private function buildAuthorizationUrl():String {
		var params = [
			"client_id=" + StringTools.urlEncode(config.clientId),
			"redirect_uri=" + StringTools.urlEncode(config.redirectUri),
			"response_type=code",
			"scope=" + StringTools.urlEncode(config.scope),
			"state=" + StringTools.urlEncode(state),
			"code_challenge=" + StringTools.urlEncode(codeChallenge),
			"code_challenge_method=S256"
		];

		return config.authorizationEndpoint + "?" + params.join("&");
	}

	private function openBrowser(url:String):Void {
		#if windows
		Sys.command("start", [url]);
		#elseif mac
		Sys.command("open", [url]);
		#else // linux and others
		Sys.command("xdg-open", [url]);
		#end
	}

	private function generateCodeVerifier():String {
		var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
		var verifier = "";
		for (i in 0...128) {
			verifier += chars.charAt(Math.floor(Math.random() * chars.length));
		}
		return verifier;
	}

	private function generateCodeChallenge(verifier:String):String {
		var hash = Sha256.encode(verifier);
		var challenge = Base64.encode(hash.toBytes())
			.toString()
			.split("=").join("")
			.split("+").join("-")
			.split("/").join("_");
		return challenge;
	}

	private function generateState():String {
		var random = Std.string(Math.floor(Math.random() * 1000000000));
		var timestamp = Std.string(Sys.time());
		return Sha256.encode(random + timestamp);
	}

	public function cleanup():Void {
		if (callbackServer != null) {
			callbackServer.stop();
		}
	}
}

typedef DesktopOAuthConfig = {
	var clientId:String;
	var ?clientSecret:String; // Optional, not recommended for desktop apps
	var authorizationEndpoint:String;
	var tokenEndpoint:String;
	var scope:String;
	var redirectUri:String; // e.g., "http://localhost:8080/callback"
	var ?callbackPort:Int; // Default 8080
	var ?timeoutSeconds:Int; // Default 300 (5 minutes)
}

typedef AuthorizationResult = {
	var code:String;
	var state:String;
	var codeVerifier:String;
}

typedef OAuthTokenResponse = {
	var accessToken:String;
	var refreshToken:Null<String>;
	var expiresIn:Int;
	var tokenType:String;
	var scope:Null<String>;
}

/**
 * Simple loopback HTTP server for OAuth callback
 */
class LoopbackServer {
	private var socket:Socket;
	private var port:Int;
	private var running:Bool = false;

	public function new(port:Int) {
		this.port = port;
		socket = new Socket();
	}

	public function waitForCallback(timeoutSeconds:Int):OAuthCallback {
		socket.bind(new Host("127.0.0.1"), port);
		socket.listen(1);
		running = true;

		trace('Loopback server listening on http://127.0.0.1:${port}');

		try {
			// Accept connection with timeout
			socket.setTimeout(timeoutSeconds);
			var client = socket.accept();
			
			// Read HTTP request
			var request = "";
			var buffer = haxe.io.Bytes.alloc(4096);
			
			try {
				var bytesRead = client.input.readBytes(buffer, 0, 4096);
				request = buffer.sub(0, bytesRead).toString();
			} catch (e:Dynamic) {
				trace("Error reading request: " + e);
			}

			// Parse callback parameters from request
			var callback = parseCallback(request);

			// Send success response to browser
			var response = buildSuccessResponse();
			client.output.writeString(response);
			client.output.flush();
			client.close();

			stop();
			return callback;
		} catch (e:Dynamic) {
			stop();
			throw "Timeout waiting for OAuth callback: " + Std.string(e);
		}
	}

	private function parseCallback(request:String):OAuthCallback {
		// Extract query string from GET request
		// Format: GET /callback?code=...&state=... HTTP/1.1
		var lines = request.split("\n");
		if (lines.length == 0) {
			throw "Invalid callback request";
		}

		var requestLine = lines[0];
		var parts = requestLine.split(" ");
		if (parts.length < 2) {
			throw "Invalid callback request format";
		}

		var path = parts[1];
		var queryStart = path.indexOf("?");
		if (queryStart == -1) {
			throw "No query parameters in callback";
		}

		var query = path.substr(queryStart + 1);
		var params = new Map<String, String>();
		
		for (pair in query.split("&")) {
			var kv = pair.split("=");
			if (kv.length == 2) {
				params.set(StringTools.urlDecode(kv[0]), StringTools.urlDecode(kv[1]));
			}
		}

		return {
			code: params.get("code"),
			state: params.get("state"),
			error: params.get("error")
		};
	}

	private function buildSuccessResponse():String {
		var html = '<!DOCTYPE html>
<html>
<head>
	<meta charset="UTF-8">
	<title>Authorization Success</title>
	<style>
		body {
			font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
			display: flex;
			justify-content: center;
			align-items: center;
			height: 100vh;
			margin: 0;
			background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
		}
		.container {
			background: white;
			padding: 40px;
			border-radius: 10px;
			box-shadow: 0 10px 40px rgba(0,0,0,0.1);
			text-align: center;
			max-width: 400px;
		}
		.success-icon {
			font-size: 64px;
			color: #10b981;
			margin-bottom: 20px;
		}
		h1 {
			color: #1f2937;
			margin: 0 0 10px 0;
		}
		p {
			color: #6b7280;
			margin: 0;
		}
	</style>
</head>
<body>
	<div class="container">
		<div class="success-icon">✓</div>
		<h1>Authorization Successful!</h1>
		<p>You can close this window and return to the application.</p>
	</div>
	<script>
		// Auto-close after 3 seconds
		setTimeout(() => window.close(), 3000);
	</script>
</body>
</html>';

		var response = "HTTP/1.1 200 OK\r\n";
		response += "Content-Type: text/html; charset=UTF-8\r\n";
		response += "Content-Length: " + html.length + "\r\n";
		response += "Connection: close\r\n";
		response += "\r\n";
		response += html;

		return response;
	}

	public function stop():Void {
		if (running) {
			running = false;
			socket.close();
		}
	}
}

typedef OAuthCallback = {
	var code:Null<String>;
	var state:Null<String>;
	var error:Null<String>;
}
