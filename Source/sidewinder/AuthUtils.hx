package sidewinder;

import sidewinder.Router.Request;
import sidewinder.Router.Response;
import haxe.Json;
import haxe.crypto.Sha256;

/**
 * Authentication Utilities
 * Helper functions for common authentication tasks
 */
class AuthUtils {
	/**
	 * Extract token from request
	 * Tries multiple sources: Authorization header, cookie, query param
	 */
	public static function extractToken(req:Request):Null<String> {
		// Try Authorization header
		var authHeader = req.headers.get("Authorization");
		if (authHeader != null && StringTools.startsWith(authHeader, "Bearer ")) {
			return authHeader.substr(7);
		}

		// Try auth_token cookie
		var cookieToken = req.cookies.get("auth_token");
		if (cookieToken != null) {
			return cookieToken;
		}

		// Try query parameter
		var queryToken = req.query.get("token");
		if (queryToken != null) {
			return queryToken;
		}

		return null;
	}

	/**
	 * Check if request is authenticated
	 */
	public static function isAuthenticated(req:Request):Bool {
		var authContext = AuthMiddleware.getAuthContext(req);
		return authContext != null && authContext.authenticated;
	}

	/**
	 * Get authenticated user ID from request
	 */
	public static function getUserId(req:Request):Null<Int> {
		var authContext = AuthMiddleware.getAuthContext(req);
		if (authContext != null && authContext.authenticated) {
			return authContext.userId;
		}
		return null;
	}

	/**
	 * Get OAuth provider from request
	 */
	public static function getProvider(req:Request):Null<String> {
		var authContext = AuthMiddleware.getAuthContext(req);
		if (authContext != null && authContext.session != null) {
			return authContext.session.provider;
		}
		return null;
	}

	/**
	 * Generate PKCE code verifier (RFC 7636)
	 */
	public static function generatePkceVerifier():String {
		var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
		var verifier = "";
		// Code verifier should be 43-128 characters, using 128 for maximum security
		for (i in 0...128) {
			verifier += chars.charAt(Math.floor(Math.random() * chars.length));
		}
		return verifier;
	}

	/**
	 * Generate PKCE code challenge from verifier
	 */
	public static function generatePkceChallenge(verifier:String):String {
		var hash = Sha256.encode(verifier);
		var challenge = haxe.crypto.Base64.encode(hash.toBytes())
			.toString()
			.split("=").join("")
			.split("+").join("-")
			.split("/").join("_");
		return challenge;
	}

	/**
	 * Generate random state for CSRF protection
	 */
	public static function generateState():String {
		var random = Std.string(Math.floor(Math.random() * 1000000000));
		var timestamp = Std.string(Sys.time());
		var combined = random + timestamp;
		return Sha256.encode(combined).toUpperCase();
	}

	/**
	 * Create a JSON error response
	 */
	public static function createErrorResponse(status:Int, message:String):String {
		return Json.stringify({
			error: true,
			status: status,
			message: message
		});
	}

	/**
	 * Create a JSON success response
	 */
	public static function createSuccessResponse(data:Dynamic):String {
		return Json.stringify({
			success: true,
			data: data
		});
	}

	/**
	 * Send JSON response with status
	 */
	public static function sendJson(res:Response, status:Int, data:Dynamic):Void {
		res.sendResponse(cast(status, snake.http.HTTPStatus));
		res.setHeader("Content-Type", "application/json");
		res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
		res.setHeader("Pragma", "no-cache");
		res.setHeader("Expires", "0");
		res.endHeaders();
		res.write(Json.stringify(data));
		res.end();
	}

	/**
	 * Require authentication for handler
	 * Returns false and sends 401 if not authenticated
	 */
	public static function requireAuth(req:Request, res:Response):Bool {
		var authContext = AuthMiddleware.getAuthContext(req);
		if (authContext == null || !authContext.authenticated) {
			sendJson(res, 401, {
				error: "Unauthorized",
				message: "Authentication required"
			});
			return false;
		}
		return true;
	}

	/**
	 * Require specific provider for handler
	 */
	public static function requireProvider(req:Request, res:Response, provider:String):Bool {
		var authContext = AuthMiddleware.getAuthContext(req);
		if (authContext == null || !authContext.authenticated) {
			sendJson(res, 401, {
				error: "Unauthorized",
				message: "Authentication required"
			});
			return false;
		}

		if (authContext.session.provider != provider) {
			sendJson(res, 403, {
				error: "Forbidden",
				message: "This resource requires " + provider + " authentication"
			});
			return false;
		}

		return true;
	}

	/**
	 * Require one of multiple providers
	 */
	public static function requireAnyProvider(req:Request, res:Response, providers:Array<String>):Bool {
		var authContext = AuthMiddleware.getAuthContext(req);
		if (authContext == null || !authContext.authenticated) {
			sendJson(res, 401, {
				error: "Unauthorized",
				message: "Authentication required"
			});
			return false;
		}

		if (providers.indexOf(authContext.session.provider) == -1) {
			sendJson(res, 403, {
				error: "Forbidden",
				message: "This resource requires one of: " + providers.join(", ")
			});
			return false;
		}

		return true;
	}

	/**
	 * Verify that user belongs to request (prevent unauthorized access to other users' data)
	 */
	public static function requireOwnResource(req:Request, res:Response, targetUserId:Int):Bool {
		var authContext = AuthMiddleware.getAuthContext(req);
		if (authContext == null || !authContext.authenticated) {
			sendJson(res, 401, {
				error: "Unauthorized",
				message: "Authentication required"
			});
			return false;
		}

		if (authContext.userId != targetUserId) {
			sendJson(res, 403, {
				error: "Forbidden",
				message: "You don't have access to this resource"
			});
			return false;
		}

		return true;
	}

	/**
	 * Format OAuth config for response (without sensitive data)
	 */
	public static function formatOAuthConfig(config:IOAuthService.OAuthConfig):Dynamic {
		return {
			provider: config.provider,
			clientId: config.clientId,
			scope: config.scope,
			redirectUri: config.redirectUri,
			authorizationEndpoint: config.authorizationEndpoint
		};
	}

	/**
	 * Format session for response (safe to send to client)
	 */
	public static function formatSession(session:AuthSession):Dynamic {
		return {
			sessionId: session.sessionId,
			userId: session.userId,
			provider: session.provider,
			expiresAt: session.expiresAt.toString(),
			createdAt: session.token.createdAt.toString()
		};
	}

	/**
	 * Get OAuth provider base URL (useful for frontend redirects)
	 */
	public static function getOAuthUrl(provider:String, ?usePkce:Bool = false):String {
		var query = usePkce ? "?use_pkce=true" : "";
		return "/oauth/authorize/" + provider + query;
	}

	/**
	 * Calculate time until token expiry
	 */
	public static function getTimeUntilExpiry(token:AuthToken):Int {
		var expiryTime = token.expiresAt.getTime();
		var nowTime = Date.now().getTime();
		var remaining = Math.floor((expiryTime - nowTime) / 1000); // in seconds
		return remaining > 0 ? remaining : 0;
	}

	/**
	 * Check if token is about to expire (within 5 minutes)
	 */
	public static function isTokenExpiringSoon(token:AuthToken, thresholdSeconds:Int = 300):Bool {
		return getTimeUntilExpiry(token) < thresholdSeconds;
	}

	/**
	 * Create URL-safe token for sensitive operations
	 */
	public static function createVerificationToken(userId:Int, expirySeconds:Int = 3600):String {
		var timestamp = Std.string(Sys.time());
		var random = Std.string(Math.floor(Math.random() * 1000000000));
		var combined = Std.string(userId) + timestamp + random + expirySeconds;
		return haxe.crypto.Base64.encode(Sha256.encode(combined).toBytes()).toString();
	}
}
