package sidewinder;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.crypto.Base64;
import sidewinder.Router.Request;
import sidewinder.Router.Response;

/**
 * OAuth Controller - Handles OAuth authorization flow endpoints
 */
class OAuthController {
	private var authService:IAuthService;
	private var stateCache:Map<String, {createdAt:Date, codeChallenge:Null<String>}> = new Map();

	public function new(authService:IAuthService) {
		this.authService = authService;
	}

	/**
	 * GET /oauth/authorize/:provider
	 * Redirects user to OAuth provider
	 * Query params: ?redirect_uri=...&use_pkce=true
	 */
	public function authorize(req:Request, res:Response):Void {
		var provider = req.params.get("provider");
		if (provider == null || provider == "") {
			sendJsonError(res, 400, "Provider is required");
			return;
		}

		try {
			var oauthService = authService.getOAuthProvider(provider);
			
			// Generate state for CSRF protection
			var state = generateState();
			
			// Generate PKCE challenge if requested
			var codeChallenge:Null<String> = null;
			var usePkce = req.query.get("use_pkce") == "true";
			if (usePkce) {
				codeChallenge = generatePkceChallenge();
			}
			
			// Store state and code challenge for later verification
			stateCache.set(state, {
				createdAt: Date.now(),
				codeChallenge: codeChallenge
			});
			
			// Get authorization URL
			var authUrl = oauthService.getAuthorizationUrl(state, codeChallenge);
			
			// Redirect to OAuth provider
			res.sendResponse(snake.http.HTTPStatus.FOUND);
			res.setHeader("Location", authUrl);
			res.endHeaders();
			res.end();
		} catch (e:Dynamic) {
			sendJsonError(res, 500, "OAuth error: " + Std.string(e));
		}
	}

	/**
	 * GET /oauth/callback/:provider
	 * OAuth provider redirects back here with authorization code
	 * Query params: ?code=...&state=...
	 */
	public function callback(req:Request, res:Response):Void {
		var provider = req.params.get("provider");
		var code = req.query.get("code");
		var state = req.query.get("state");
		var error = req.query.get("error");
		
		if (error != null) {
			sendJsonError(res, 400, "OAuth error: " + error);
			return;
		}

		if (code == null || code == "") {
			sendJsonError(res, 400, "Authorization code is missing");
			return;
		}

		if (state == null || state == "") {
			sendJsonError(res, 400, "State is missing");
			return;
		}

		// Verify state
		var cachedState = stateCache.get(state);
		if (cachedState == null) {
			sendJsonError(res, 400, "Invalid or expired state");
			return;
		}

		// Check state expiration (5 minutes)
		var ageMs = Date.now().getTime() - cachedState.createdAt.getTime();
		if (ageMs > 5 * 60 * 1000) {
			stateCache.remove(state);
			sendJsonError(res, 400, "State has expired");
			return;
		}

		try {
			// Exchange code for token (and get user info)
			var session = authService.authenticateWithOAuth(code, provider, null);
			
			// Clean up state
			stateCache.remove(state);
			
			// Send response with session
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			
			// Set auth token cookie
			res.setCookie("auth_token", session.token.token, {
				path: "/",
				httpOnly: true,
				secure: false, // Set to true in production with HTTPS
				maxAge: Std.string(24 * 60 * 60) // 24 hours
			});
			
			res.endHeaders();
			res.write(Json.stringify({
				success: true,
				session: {
					sessionId: session.sessionId,
					userId: session.userId,
					provider: session.provider,
					expiresAt: session.expiresAt.toString()
				},
				token: session.token.token
			}));
			res.end();
		} catch (e:Dynamic) {
			sendJsonError(res, 500, "Authentication failed: " + Std.string(e));
		}
	}

	/**
	 * GET /oauth/logout
	 * Logout user
	 */
	public function logout(req:Request, res:Response):Void {
		var authContext = AuthMiddleware.getAuthContext(req);
		
		if (authContext != null && authContext.session != null) {
			authService.revokeSession(authContext.session.sessionId);
		}
		
		res.sendResponse(snake.http.HTTPStatus.OK);
		res.setHeader("Content-Type", "application/json");
		
		// Clear auth cookie
		res.setCookie("auth_token", "", {
			path: "/",
			httpOnly: true,
			maxAge: "0"
		});
		
		res.endHeaders();
		res.write(Json.stringify({
			success: true,
			message: "Logged out successfully"
		}));
		res.end();
	}

	/**
	 * GET /oauth/user
	 * Get current authenticated user info
	 */
	public function getCurrentUser(req:Request, res:Response):Void {
		var authContext = AuthMiddleware.getAuthContext(req);
		
		if (authContext == null || !authContext.authenticated || authContext.session == null) {
			sendJsonError(res, 401, "Not authenticated");
			return;
		}
		
		res.sendResponse(snake.http.HTTPStatus.OK);
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		res.write(Json.stringify({
			userId: authContext.session.userId,
			provider: authContext.session.provider,
			expiresAt: authContext.session.expiresAt.toString()
		}));
		res.end();
	}

	/**
	 * POST /oauth/refresh
	 * Refresh authentication session
	 */
	public function refreshSession(req:Request, res:Response):Void {
		var authContext = AuthMiddleware.getAuthContext(req);
		
		if (authContext == null || !authContext.authenticated || authContext.session == null) {
			sendJsonError(res, 401, "Not authenticated");
			return;
		}
		
		try {
			var newSession = authService.refreshSession(authContext.session.sessionId);
			if (newSession == null) {
				sendJsonError(res, 401, "Failed to refresh session");
				return;
			}
			
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			
			// Update auth token cookie
			res.setCookie("auth_token", newSession.token.token, {
				path: "/",
				httpOnly: true,
				maxAge: Std.string(24 * 60 * 60)
			});
			
			res.endHeaders();
			res.write(Json.stringify({
				success: true,
				session: {
					sessionId: newSession.sessionId,
					userId: newSession.userId,
					provider: newSession.provider,
					expiresAt: newSession.expiresAt.toString()
				},
				token: newSession.token.token
			}));
			res.end();
		} catch (e:Dynamic) {
			sendJsonError(res, 500, "Session refresh failed: " + Std.string(e));
		}
	}

	private function generateState():String {
		var random = Std.string(Math.floor(Math.random() * 1000000000));
		var timestamp = Std.string(Sys.time());
		var combined = random + timestamp;
		return Sha256.encode(combined).toUpperCase();
	}

	private function generatePkceChallenge():String {
		// Generate code verifier (43-128 characters)
		var verifier = generateCodeVerifier();
		
		// Create challenge from verifier
		var challenge = Base64.encode(Sha256.encode(verifier).toBytes())
			.toString()
			.split("=").join("")
			.split("+").join("-")
			.split("/").join("_");
		
		return challenge;
	}

	private function generateCodeVerifier():String {
		var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
		var verifier = "";
		for (i in 0...128) {
			verifier += chars.charAt(Math.floor(Math.random() * chars.length));
		}
		return verifier;
	}

	private function sendJsonError(res:Response, status:Int, message:String):Void {
		res.sendResponse(cast(status, snake.http.HTTPStatus));
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		res.write(Json.stringify({
			error: message
		}));
		res.end();
	}
}
