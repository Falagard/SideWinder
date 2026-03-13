package sidewinder.interfaces;
import sidewinder.interfaces.IOAuthService.OAuthUserInfo;
import sidewinder.interfaces.User;

// No implementation imports allowed in interfaces


import hx.injection.Service;

class OAuthConfig {
	public var clientId:String;
	public var clientSecret:String;
	public var redirectUri:String;
	public var scope:String;
	public var authorizationEndpoint:String;
	public var tokenEndpoint:String;
	public var userInfoEndpoint:String;
	public var provider:String; // e.g., "google", "github", "microsoft"

	public function new() {}
}

typedef OAuthToken = {
	var accessToken:String;
	var refreshToken:Null<String>;
	var expiresIn:Int;
	var tokenType:String;
	var createdAt:Date;
}

typedef OAuthUserInfo = {
	var id:String;
	var email:String;
	var name:String;
	var picture:Null<String>;
	var provider:String;
}

interface IOAuthService extends Service {
	/**
	 * Get the authorization URL for OAuth flow
	 * @param state - CSRF protection token
	 * @param codeChallenge - Optional PKCE code challenge for security
	 */
	public function getAuthorizationUrl(state:String, ?codeChallenge:String):String;

	/**
	 * Exchange authorization code for access token
	 * @param code - Authorization code from OAuth provider
	 * @param codeVerifier - Optional PKCE code verifier for security
	 */
	public function exchangeCodeForToken(code:String, ?codeVerifier:String):OAuthToken;

	/**
	 * Refresh an access token
	 */
	public function refreshAccessToken(refreshToken:String):OAuthToken;

	/**
	 * Get user information from OAuth provider
	 */
	public function getUserInfo(accessToken:String):OAuthUserInfo;

	/**
	 * Get the OAuth provider name
	 */
	public function getProvider():String;

	/**
	 * Get OAuth configuration
	 */
	public function getConfig():OAuthConfig;
}
