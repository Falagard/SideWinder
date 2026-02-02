package sidewinder;

import haxe.Http;
import haxe.Json;
import haxe.Timer;

/**
 * Device Flow OAuth Client (RFC 8628)
 * For devices with limited input capabilities or no browser
 * User authenticates on a separate device (phone/computer)
 * 
 * Flow:
 * 1. Request device code
 * 2. Display user code and verification URL to user
 * 3. Poll for authorization
 * 4. Receive access token when user completes authentication
 */
class DeviceFlowOAuthClient {
	private var config:DeviceFlowConfig;

	public function new(config:DeviceFlowConfig) {
		this.config = config;
	}

	/**
	 * Start device authorization flow
	 * Returns device code and user instructions
	 */
	public function requestDeviceCode():DeviceCodeResponse {
		var http = new Http(config.deviceAuthorizationEndpoint);
		http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		http.setHeader("Accept", "application/json");

		var params = [
			"client_id=" + StringTools.urlEncode(config.clientId),
			"scope=" + StringTools.urlEncode(config.scope)
		];

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
			throw "Failed to request device code: " + Std.string(e);
		}

		if (error != "") {
			throw "Device code request error: " + error;
		}

		var parsed:Dynamic = Json.parse(result);

		if (parsed.error != null) {
			throw "OAuth error: " + parsed.error;
		}

		return {
			deviceCode: parsed.device_code,
			userCode: parsed.user_code,
			verificationUri: parsed.verification_uri,
			verificationUriComplete: parsed.verification_uri_complete,
			expiresIn: parsed.expires_in ?? 600,
			interval: parsed.interval ?? 5
		};
	}

	/**
	 * Poll for authorization (blocking)
	 * Call after displaying user code to user
	 */
	public function pollForAuthorization(deviceCodeResponse:DeviceCodeResponse):OAuthTokenResponse {
		var deviceCode = deviceCodeResponse.deviceCode;
		var interval = deviceCodeResponse.interval;
		var expiresAt = Date.now().getTime() + (deviceCodeResponse.expiresIn * 1000);

		trace('Polling for authorization every ${interval} seconds...');

		while (Date.now().getTime() < expiresAt) {
			Sys.sleep(interval);

			var result = attemptTokenRequest(deviceCode);

			if (result.success) {
				return result.token;
			}

			if (result.error == "authorization_pending") {
				trace('Authorization pending...');
				continue;
			}

			if (result.error == "slow_down") {
				trace('Slow down requested, increasing interval...');
				interval += 5;
				continue;
			}

			if (result.error == "expired_token") {
				throw "Device code expired";
			}

			if (result.error == "access_denied") {
				throw "User denied authorization";
			}

			throw "Unexpected error: " + result.error;
		}

		throw "Authorization timed out";
	}

	/**
	 * Complete flow: request code + poll for token
	 * Returns both the user instructions and token
	 */
	public function authenticate():DeviceFlowResult {
		var deviceCode = requestDeviceCode();
		
		// Display instructions to user
		displayInstructions(deviceCode);

		// Poll for authorization
		var token = pollForAuthorization(deviceCode);

		return {
			deviceCode: deviceCode,
			token: token
		};
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

	private function attemptTokenRequest(deviceCode:String):TokenAttemptResult {
		var http = new Http(config.tokenEndpoint);
		http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		http.setHeader("Accept", "application/json");

		var params = [
			"grant_type=urn:ietf:params:oauth:grant-type:device_code",
			"device_code=" + StringTools.urlEncode(deviceCode),
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
			return {
				success: false,
				error: "request_failed",
				token: null
			};
		}

		if (error != "") {
			return {
				success: false,
				error: "network_error",
				token: null
			};
		}

		var parsed:Dynamic = Json.parse(result);

		// Check for OAuth error
		if (parsed.error != null) {
			return {
				success: false,
				error: parsed.error,
				token: null
			};
		}

		// Success!
		return {
			success: true,
			error: null,
			token: {
				accessToken: parsed.access_token,
				refreshToken: parsed.refresh_token,
				expiresIn: parsed.expires_in ?? 3600,
				tokenType: parsed.token_type ?? "Bearer",
				scope: parsed.scope
			}
		};
	}

	private function displayInstructions(deviceCode:DeviceCodeResponse):Void {
		trace("\n" + "=".repeat(60));
		trace("DEVICE AUTHORIZATION");
		trace("=".repeat(60));
		trace("");
		trace("1. Visit: " + deviceCode.verificationUri);
		trace("2. Enter code: " + deviceCode.userCode);
		trace("");
		
		if (deviceCode.verificationUriComplete != null) {
			trace("Or open this URL directly:");
			trace(deviceCode.verificationUriComplete);
			trace("");
		}
		
		trace("Waiting for authorization...");
		trace("Code expires in " + deviceCode.expiresIn + " seconds");
		trace("=".repeat(60) + "\n");
	}
}

typedef DeviceFlowConfig = {
	var clientId:String;
	var ?clientSecret:String;
	var deviceAuthorizationEndpoint:String;
	var tokenEndpoint:String;
	var scope:String;
}

typedef DeviceCodeResponse = {
	var deviceCode:String;
	var userCode:String;
	var verificationUri:String;
	var ?verificationUriComplete:String;
	var expiresIn:Int;
	var interval:Int;
}

typedef DeviceFlowResult = {
	var deviceCode:DeviceCodeResponse;
	var token:OAuthTokenResponse;
}

typedef TokenAttemptResult = {
	var success:Bool;
	var error:Null<String>;
	var token:Null<OAuthTokenResponse>;
}

typedef OAuthTokenResponse = {
	var accessToken:String;
	var refreshToken:Null<String>;
	var expiresIn:Int;
	var tokenType:String;
	var scope:Null<String>;
}

private class StringToolsExtension {
	public static function repeat(s:String, count:Int):String {
		var result = "";
		for (i in 0...count) {
			result += s;
		}
		return result;
	}
}
