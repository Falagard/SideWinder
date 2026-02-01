package sidewinder;

import haxe.Json;
import sidewinder.Router.Request;
import sidewinder.Router.Response;

/**
 * Example Authentication Application Routes
 * Demonstrates how to use OAuth and authentication middleware
 */
class ExampleAuthApp {
	public static function setupAuthRoutes():Void {
		// Get services from DI
		var authService = DI.get(IAuthService);
		var authMiddleware = new AuthMiddleware(authService);
		var oauthController = new OAuthController(authService);

		// ============================================
		// PUBLIC ROUTES - No authentication required
		// ============================================

		// Welcome page
		App.get("/", function(req:Request, res:Response) {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify({
				message: "Welcome to SideWinder",
				login: "Visit /login for OAuth login options"
			}));
			res.end();
		});

		// Login page with provider options
		App.get("/login", function(req:Request, res:Response) {
			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify({
				message: "Available OAuth providers",
				providers: [
					{
						name: "Google",
						url: "/oauth/authorize/google"
					},
					{
						name: "GitHub",
						url: "/oauth/authorize/github"
					},
					{
						name: "Microsoft",
						url: "/oauth/authorize/microsoft"
					}
				]
			}));
			res.end();
		});

		// ============================================
		// OAUTH ENDPOINTS
		// ============================================

		// OAuth authorization - redirects to provider
		App.get("/oauth/authorize/:provider", function(req:Request, res:Response) {
			oauthController.authorize(req, res);
		});

		// OAuth callback - called by provider after user authenticates
		App.get("/oauth/callback/:provider", function(req:Request, res:Response) {
			oauthController.callback(req, res);
		});

		// ============================================
		// AUTHENTICATED ROUTES
		// ============================================

		// Apply protection middleware to subsequent routes
		App.use(authMiddleware.protect());

		// Get current user info
		App.get("/api/me", function(req:Request, res:Response) {
			var authContext = AuthMiddleware.getAuthContext(req);

			if (authContext == null || !authContext.authenticated) {
				sendJsonError(res, 401, "Not authenticated");
				return;
			}

			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify({
				userId: authContext.userId,
				provider: authContext.session.provider,
				sessionId: authContext.session.sessionId,
				expiresAt: authContext.session.expiresAt.toString(),
				token: authContext.token
			}));
			res.end();
		});

		// Logout endpoint
		App.get("/api/logout", function(req:Request, res:Response) {
			oauthController.logout(req, res);
		});

		// Refresh session
		App.post("/api/refresh", function(req:Request, res:Response) {
			oauthController.refreshSession(req, res);
		});

		// Example protected endpoint - get user profile
		App.get("/api/profile", function(req:Request, res:Response) {
			var authContext = AuthMiddleware.getAuthContext(req);

			// In a real app, you'd fetch user data from database
			var userService = DI.get(IUserService);
			var user = userService.getById(authContext.userId);

			if (user == null) {
				sendJsonError(res, 404, "User not found");
				return;
			}

			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify({
				id: user.id,
				name: user.name,
				email: user.email,
				provider: authContext.session.provider
			}));
			res.end();
		});

		// Example protected endpoint - get protected resource
		App.get("/api/protected-resource", function(req:Request, res:Response) {
			var authContext = AuthMiddleware.getAuthContext(req);

			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify({
				message: "This is a protected resource",
				userId: authContext.userId,
				provider: authContext.session.provider,
				timestamp: Date.now().toString()
			}));
			res.end();
		});

		// Admin-only endpoint - requires specific provider
		App.use(authMiddleware.protect(["github", "microsoft"]));

		App.get("/api/admin", function(req:Request, res:Response) {
			var authContext = AuthMiddleware.getAuthContext(req);

			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify({
				message: "Admin resource - GitHub or Microsoft users only",
				userId: authContext.userId,
				provider: authContext.session.provider
			}));
			res.end();
		});

		// ============================================
		// OPTIONAL AUTHENTICATION ROUTES
		// ============================================

		// Reset middleware to optional auth
		App.use(authMiddleware.optional());

		// Endpoint that works for both authenticated and unauthenticated users
		App.get("/api/posts", function(req:Request, res:Response) {
			var authContext = AuthMiddleware.getAuthContext(req);

			var posts:Array<Dynamic> = [
				{
					id: 1,
					title: "Hello World",
					author: "Alice",
					public: true
				},
				{
					id: 2,
					title: "Private Post",
					author: "Bob",
					public: false
				}
			];

			var response:Dynamic = {
				posts: posts
			};

			// If user is authenticated, include their user ID
			if (authContext != null && authContext.authenticated) {
				response.userId = authContext.userId;
				response.message = "You are logged in as provider: " + authContext.session.provider;
			} else {
				response.message = "You are viewing as guest";
			}

			res.sendResponse(snake.http.HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			res.write(Json.stringify(response));
			res.end();
		});
	}

	private static function sendJsonError(res:Response, status:Int, message:String):Void {
		res.sendResponse(cast(status, snake.http.HTTPStatus));
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		res.write(Json.stringify({
			error: message
		}));
		res.end();
	}
}
