package sidewinder;

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
}

interface IAuthService extends Service {
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
}
