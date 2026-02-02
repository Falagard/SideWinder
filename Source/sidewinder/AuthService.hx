MultipartParserpackage sidewinder;

import haxe.crypto.Sha256;
import haxe.crypto.Base64;
import sidewinder.IAuthService;
import sidewinder.IUserService;

class AuthService implements IAuthService {
	private var oauthServices:Map<String, IOAuthService> = new Map();
	private var sessions:Map<String, AuthSession> = new Map();
	private var tokens:Map<String, AuthToken> = new Map();
	private var userService:IUserService;

	public function new(userService:IUserService) {
		this.userService = userService;
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
		// Check if user exists by email
		var existingUsers = userService.getAll();
		var existing:Null<Int> = null;
		
		for (user in existingUsers) {
			if (user.email == oauthUser.email) {
				existing = user.id;
				break;
			}
		}
		
		if (existing != null) {
			// Update existing user
			userService.update(existing, {
				id: existing,
				name: oauthUser.name,
				email: oauthUser.email
			});
			return existing;
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
			expiresAt: expiresAt
		};
		
		// Store session and token
		sessions.set(sessionId, session);
		tokens.set(token, authToken);
		
		return session;
	}

	public function validateToken(token:String):Null<AuthSession> {
		var authToken = tokens.get(token);
		if (authToken == null) {
			return null;
		}
		
		// Check if token is expired
		if (Date.now().getTime() > authToken.expiresAt.getTime()) {
			tokens.remove(token);
			return null;
		}
		
		// Find corresponding session
		for (session in sessions) {
			if (session.token.token == token) {
				return session;
			}
		}
		
		return null;
	}

	public function revokeSession(sessionId:String):Bool {
		var session = sessions.get(sessionId);
		if (session == null) {
			return false;
		}
		
		// Remove both session and token
		sessions.remove(sessionId);
		tokens.remove(session.token.token);
		return true;
	}

	public function getSessionByToken(token:String):Null<AuthSession> {
		var authToken = tokens.get(token);
		if (authToken == null) {
			return null;
		}
		
		for (session in sessions) {
			if (session.token.token == token) {
				return session;
			}
		}
		
		return null;
	}

	public function refreshSession(sessionId:String):Null<AuthSession> {
		var session = sessions.get(sessionId);
		if (session == null) {
			return null;
		}
		
		// Revoke old session
		revokeSession(sessionId);
		
		// Create new session for the same user and provider
		return createSession(session.userId, session.provider);
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
		return Base64.encode(Sha256.encode(combined).toBytes()).toString();
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
