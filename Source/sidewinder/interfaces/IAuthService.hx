package sidewinder.interfaces;
import sidewinder.interfaces.IOAuthService.OAuthUserInfo;
import sidewinder.interfaces.User;

// No implementation imports allowed in interfaces


import hx.injection.Service;

typedef AuthToken = {
	var token:String;
	var userId:Int;
	var expiresAt:Date;
	var createdAt:Date;
}

typedef AuthSession = {
	var sessionId:String;
	var userId:Int;
	var token:AuthToken;
	var provider:String;
	var expiresAt:Date;
	@:optional var permissions:Array<String>;
}

interface IAuthService extends Service {
	/**
	 * Register an OAuth service provider
	 */
	public function registerOAuthProvider(provider:String, service:IOAuthService):Void;

	/**
	 * Get an OAuth service by provider name
	 */
	public function getOAuthProvider(provider:String):IOAuthService;

	/**
	 * Authenticate with OAuth
	 */
	public function authenticateWithOAuth(code:String, provider:String, ?codeVerifier:String):AuthSession;

	/**
	 * Create or update user from OAuth data
	 */
	public function createOrUpdateUserFromOAuth(oauthUser:OAuthUserInfo):Int;

	/**
	 * Create an auth session for a user
	 */
	public function createSession(userId:Int, provider:String):AuthSession;

	/**
	 * Validate an auth token
	 */
	public function validateToken(token:String):Null<AuthSession>;

	/**
	 * Revoke an auth session
	 */
	public function revokeSession(sessionId:String):Bool;

	/**
	 * Get active session by token
	 */
	public function getSessionByToken(token:String):Null<AuthSession>;

	/**
	 * Refresh an auth session
	 */
	public function refreshSession(sessionId:String):Null<AuthSession>;

	/**
	 * Request a magic link for an email address
	 * @return A unique token to be sent to the user's email
	 */
	public function requestMagicLink(email:String):String;

	/**
	 * Authenticate with a magic link token
	 * @return The created authentication session
	 */
	public function authenticateWithMagicLink(token:String):AuthSession;

	/**
	 * Authenticate with an API key
	 * @return The created authentication session
	 */
	public function authenticateWithApiKey(apiKey:String):AuthSession;
}
