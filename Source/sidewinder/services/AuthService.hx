package sidewinder.services;
import sidewinder.interfaces.User;

import sidewinder.interfaces.IAuthService;
import sidewinder.interfaces.IUserService;
import sidewinder.interfaces.IOAuthService;
import sidewinder.interfaces.IOAuthService.OAuthUserInfo;
import sidewinder.interfaces.ICacheService;
import sidewinder.logging.HybridLogger;

import haxe.crypto.Sha256;
import haxe.crypto.Base64;


class AuthService implements IAuthService {
	private var oauthServices:Map<String, IOAuthService> = new Map();
	private var userService:IUserService;
	private var cache:ICacheService;

	public function new(userService:IUserService, cache:ICacheService) {
		this.userService = userService;
		this.cache = cache;
	}

	public function getConstructorArgs():Array<String> {
		return ["sidewinder.interfaces.IUserService", "sidewinder.interfaces.ICacheService"];
	}

	/**
	 * Register an OAuth service provider
	 */
	public function registerOAuthProvider(provider:String, service:IOAuthService):Void {
		oauthServices.set(provider, service);
	}

	/**
	 * Get an OAuth service by provider name
	 */
	public function getOAuthProvider(provider:String):IOAuthService {
		var service = oauthServices.get(provider);
		if (service == null) {
			throw "OAuth provider not registered: " + provider;
		}
		return service;
	}

	public function authenticateWithOAuth(code:String, provider:String, ?codeVerifier:String):AuthSession {
		var oauthService = getOAuthProvider(provider);
		
		// Exchange code for token
		var token = oauthService.exchangeCodeForToken(code, codeVerifier);
		
		// Get user info from provider
		var oauthUser = oauthService.getUserInfo(token.accessToken);
		
		// Create or update user
		var userId = createOrUpdateUserFromOAuth(oauthUser);
		
		// Create auth session
		return createSession(userId, provider);
	}

	public function createOrUpdateUserFromOAuth(oauthUser:OAuthUserInfo):Int {
		var existingUser = userService.getByEmail(oauthUser.email);
		
		if (existingUser != null) {
			// Update existing user
			userService.update(existingUser.id, {
				id: existingUser.id,
				name: oauthUser.name,
				email: oauthUser.email
			});
			return existingUser.id;
		} else {
			// Create new user
			var newUser = userService.create({
				id: 0, // ID will be auto-generated
				name: oauthUser.name,
				email: oauthUser.email
			});
			return newUser.id;
		}
	}

	public function createSession(userId:Int, provider:String):AuthSession {
		var sessionId = generateSessionId();
		var token = generateToken();
		var expiresAt = Date.fromTime(Date.now().getTime() + 24 * 60 * 60 * 1000); // 24 hours
		
		var user = userService.getById(userId);
		var permissions = (user != null && user.permissions != null) ? user.permissions : [];

		var authToken:AuthToken = {
			token: token,
			userId: userId,
			expiresAt: expiresAt,
			createdAt: Date.now()
		};
		
		var session:AuthSession = {
			sessionId: sessionId,
			userId: userId,
			token: authToken,
			provider: provider,
			expiresAt: expiresAt,
			permissions: permissions
		};
		
		// Store session and token in cache
		// Sessions and tokens live for 24 hours
		var ttlMs = 24 * 60 * 60 * 1000;
		cache.set("auth:session:" + sessionId, session, ttlMs);
		cache.set("auth:token:" + token, authToken, ttlMs);
		cache.set("auth:session_by_token:" + token, session, ttlMs);
		
		return session;
	}

	public function validateToken(token:String):Null<AuthSession> {
		var authToken:AuthToken = cache.get("auth:token:" + token);
		if (authToken == null) {
			return null;
		}
		
		// Check if token is expired
		if (Date.now().getTime() > authToken.expiresAt.getTime()) {
			cache.remove("auth:token:" + token);
			return null;
		}
		
		// Find corresponding session - we can't easily iterate cache, but we can store sessionId in token
		// For now, let's assume we can get session by a derivative key or store it in token
		// Actually, let's store sessionId in AuthToken for faster lookup if needed, 
		// but IAuthService defines AuthSession, let's see where sessions are used.
		return getSessionByToken(token);
	}

	public function revokeSession(sessionId:String):Bool {
		var session:AuthSession = cache.get("auth:session:" + sessionId);
		if (session == null) {
			return false;
		}
		
		// Remove both session and token
		cache.remove("auth:session:" + sessionId);
		cache.remove("auth:token:" + session.token.token);
		cache.remove("auth:session_by_token:" + session.token.token);
		return true;
	}

	public function getSessionByToken(token:String):Null<AuthSession> {
		var authToken:AuthToken = cache.get("auth:token:" + token);
		if (authToken == null) {
			return null;
		}
		
		// We could iterate but cache doesn't support it.
		// However, AuthSession contains the token, and createSession stores both.
		// To fix this without iteration, we can store a mapping or just the whole session by token.
		// Let's store session by token too.
		return cast cache.get("auth:session_by_token:" + token);
	}

	public function refreshSession(sessionId:String):Null<AuthSession> {
		var session:AuthSession = cache.get("auth:session:" + sessionId);
		if (session == null) {
			return null;
		}
		
		// Revoke old session
		revokeSession(sessionId);
		
		// Create new session for the same user and provider
		return createSession(session.userId, session.provider);
	}

	public function requestMagicLink(email:String):String {
		var token = generateToken();
		// Magic links expire in 15 minutes
		var ttlMs = 15 * 60 * 1000;
		var expiresAt = Date.fromTime(Date.now().getTime() + ttlMs);
		
		cache.set("auth:magic:" + token, {
			email: email,
			expiresAt: expiresAt
		}, ttlMs);
		
		return token;
	}

	public function authenticateWithMagicLink(token:String):AuthSession {
		var cacheKey = "auth:magic:" + token;
		
		var linkData:{email:String, expiresAt:Date} = cache.get(cacheKey);
		
		if (linkData == null) {
			throw "Invalid or expired magic link";
		}
		
		// Map data from cache might lose Date type if serialized, but InMemoryCache should preserve it.
		if (Date.now().getTime() > linkData.expiresAt.getTime()) {
			cache.remove("auth:magic:" + token);
			throw "Magic link has expired";
		}
		
		// Token is valid, remove it so it can't be reused
		cache.remove("auth:magic:" + token);
		
		// Find or create user
		var user = userService.getByEmail(linkData.email);
		var userId:Int;
		
		if (user != null) {
			userId = user.id;
		} else {
			// Extract name from email as fallback
			var name = linkData.email.split("@")[0];
			var newUser = userService.create({
				id: 0,
				name: name,
				email: linkData.email
			});
			userId = newUser.id;
		}
		
		// Create long-lived session securely
		return createSession(userId, "magic_link");
	}

	private function generateSessionId():String {
		var timestamp = Std.string(Sys.time());
		var random = Std.string(Math.floor(Math.random() * 1000000000));
		var combined = timestamp + random + UUID.create().toString();
		return Sha256.encode(combined).toUpperCase();
	}

	private function generateToken():String {
		var random = Std.string(Math.floor(Math.random() * 1000000000));
		var timestamp = Std.string(Sys.time());
		var combined = random + timestamp + UUID.create().toString();
		var combinedBytes = haxe.io.Bytes.ofString(combined);
		var hashedBytes = haxe.crypto.Sha256.make(combinedBytes);
		return Base64.encode(hashedBytes);
	}
}

// Simple UUID implementation for uniqueness
private class UUID {
	public static function create():String {
		var time = Sys.time();
		var random = Math.random();
		return Std.string(time) + "-" + Std.string(random);
	}
}
