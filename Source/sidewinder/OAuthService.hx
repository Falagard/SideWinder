package sidewinder;

import haxe.Http;
import haxe.Json;

class OAuthService implements IOAuthService {
	private var config:OAuthConfig;

	public function new(config:OAuthConfig) {
		this.config = config;
	}

	public function getAuthorizationUrl(state:String, ?codeChallenge:String):String {
		var params:Array<String> = [
			"client_id=" + StringTools.urlEncode(config.clientId),
			"redirect_uri=" + StringTools.urlEncode(config.redirectUri),
			"scope=" + StringTools.urlEncode(config.scope),
			"response_type=code",
			"state=" + StringTools.urlEncode(state)
		];

		if (codeChallenge != null) {
			params.push("code_challenge=" + StringTools.urlEncode(codeChallenge));
			params.push("code_challenge_method=S256");
		}

		return config.authorizationEndpoint + "?" + params.join("&");
	}

	public function exchangeCodeForToken(code:String, ?codeVerifier:String):OAuthToken {
		var http = new Http(config.tokenEndpoint);
		http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		http.setHeader("Accept", "application/json");

		var params = [
			"grant_type=authorization_code",
			"code=" + StringTools.urlEncode(code),
			"client_id=" + StringTools.urlEncode(config.clientId),
			"client_secret=" + StringTools.urlEncode(config.clientSecret),
			"redirect_uri=" + StringTools.urlEncode(config.redirectUri)
		];

		if (codeVerifier != null) {
			params.push("code_verifier=" + StringTools.urlEncode(codeVerifier));
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
			throw "Failed to exchange code for token: " + Std.string(e);
		}

		if (error != "") {
			throw "OAuth token exchange error: " + error;
		}

		var parsed:Dynamic = null;
		try {
			parsed = Json.parse(result);
		} catch (e:Dynamic) {
			throw "Failed to parse OAuth response: " + Std.string(e);
		}

		if (parsed.error != null) {
			throw "OAuth error: " + parsed.error + " - " + (parsed.error_description ?? "");
		}

		return {
			accessToken: parsed.access_token,
			refreshToken: parsed.refresh_token,
			expiresIn: parsed.expires_in ?? 3600,
			tokenType: parsed.token_type ?? "Bearer",
			createdAt: Date.now()
		};
	}

	public function refreshAccessToken(refreshToken:String):OAuthToken {
		var http = new Http(config.tokenEndpoint);
		http.setHeader("Content-Type", "application/x-www-form-urlencoded");
		http.setHeader("Accept", "application/json");

		var params = [
			"grant_type=refresh_token",
			"refresh_token=" + StringTools.urlEncode(refreshToken),
			"client_id=" + StringTools.urlEncode(config.clientId),
			"client_secret=" + StringTools.urlEncode(config.clientSecret)
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
			throw "Failed to refresh token: " + Std.string(e);
		}

		if (error != "") {
			throw "Token refresh error: " + error;
		}

		var parsed:Dynamic = null;
		try {
			parsed = Json.parse(result);
		} catch (e:Dynamic) {
			throw "Failed to parse refresh response: " + Std.string(e);
		}

		if (parsed.error != null) {
			throw "OAuth error: " + parsed.error;
		}

		return {
			accessToken: parsed.access_token,
			refreshToken: parsed.refresh_token ?? refreshToken,
			expiresIn: parsed.expires_in ?? 3600,
			tokenType: parsed.token_type ?? "Bearer",
			createdAt: Date.now()
		};
	}

	public function getUserInfo(accessToken:String):OAuthUserInfo {
		var http = new Http(config.userInfoEndpoint);
		http.setHeader("Authorization", "Bearer " + accessToken);
		http.setHeader("Accept", "application/json");

		var result:String = "";
		var error:String = "";

		http.onData = function(data:String) {
			result = data;
		};

		http.onError = function(err:String) {
			error = err;
		};

		try {
			http.request(false);
		} catch (e:Dynamic) {
			throw "Failed to fetch user info: " + Std.string(e);
		}

		if (error != "") {
			throw "User info error: " + error;
		}

		var parsed:Dynamic = null;
		try {
			parsed = Json.parse(result);
		} catch (e:Dynamic) {
			throw "Failed to parse user info: " + Std.string(e);
		}

		// Map OAuth provider-specific fields to standard format
		return {
			id: parsed.id ?? parsed.sub ?? parsed.user_id ?? "",
			email: parsed.email ?? parsed.mail ?? "",
			name: parsed.name ?? parsed.login ?? "",
			picture: parsed.picture ?? parsed.avatar_url ?? null,
			provider: config.provider
		};
	}

	public function getProvider():String {
		return config.provider;
	}

	public function getConfig():OAuthConfig {
		return config;
	}
}
