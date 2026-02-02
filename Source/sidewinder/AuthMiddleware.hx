package sidewinder;

import sidewinder.Router.Request;
import sidewinder.Router.Response;
import sidewinder.Router.Middleware;
import haxe.Json;

typedef AuthContext = {
	var authenticated:Bool;
	var userId:Null<Int>;
	var session:Null<AuthSession>;
	var token:Null<String>;
}

class AuthMiddleware {
	private var authService:IAuthService;
	private var protectedPaths:Array<String> = [];
	private var publicPaths:Array<String> = [];

	public function new(authService:IAuthService) {
		this.authService = authService;
	}

	/**
	 * Create a middleware function that validates authentication
	 * @param requiredAuth - If true, request must be authenticated
	 * @return Middleware function
	 */
	public function create(requiredAuth:Bool = false):Middleware {
		return function(req:Request, res:Response, next:Void->Void) {
			var authContext = extractAuth(req);
			
			// Store auth context in request for handlers to access
			req.authContext = authContext;
			
			// If authentication is required and user is not authenticated, return 401
			if (requiredAuth && !authContext.authenticated) {
				sendUnauthorized(res);
				return;
			}
			
			// Continue to next middleware/handler
			next();
		};
	}

	/**
	 * Extract authentication information from request
	 */
	private function extractAuth(req:Request):AuthContext {
		var context:AuthContext = {
			authenticated: false,
			userId: null,
			session: null,
			token: null
		};

		// Try to get token from Authorization header (Bearer token)
		var authHeader = req.headers.get("Authorization");
		if (authHeader != null && StringTools.startsWith(authHeader, "Bearer ")) {
			var token = authHeader.substr(7);
			var session = authService.validateToken(token);
			if (session != null) {
				context.authenticated = true;
				context.userId = session.userId;
				context.session = session;
				context.token = token;
				return context;
			}
		}

		// Try to get token from cookies
		var sessionCookie = req.cookies.get("auth_token");
		if (sessionCookie != null) {
			var session = authService.validateToken(sessionCookie);
			if (session != null) {
				context.authenticated = true;
				context.userId = session.userId;
				context.session = session;
				context.token = sessionCookie;
				return context;
			}
		}

		// Try to get session ID from cookies
		var sessionId = req.cookies.get("session_id");
		if (sessionId != null) {
			// In a real app, you'd look up the session by ID
			// For now, we rely on token validation above
		}

		return context;
	}

	/**
	 * Create middleware for specific route protection
	 */
	public function protect(allowedProviders:Array<String> = null):Middleware {
		return function(req:Request, res:Response, next:Void->Void) {
			var authContext = extractAuth(req);
			
			if (!authContext.authenticated) {
				sendUnauthorized(res);
				return;
			}

			// Check if session provider is in allowed list
			if (allowedProviders != null && authContext.session != null) {
				if (allowedProviders.indexOf(authContext.session.provider) == -1) {
					sendForbidden(res, "This provider is not allowed for this route");
					return;
				}
			}

			req.authContext = authContext;
			next();
		};
	}

	/**
	 * Optional authentication middleware - doesn't fail if auth is missing
	 */
	public function optional():Middleware {
		return function(req:Request, res:Response, next:Void->Void) {
			var authContext = extractAuth(req);
			req.authContext = authContext;
			next();
		};
	}

	/**
	 * Get the auth context from a request
	 */
	public static function getAuthContext(req:Request):Null<AuthContext> {
		return req.authContext;
	}

	private function sendUnauthorized(res:Response):Void {
		res.sendResponse(snake.http.HTTPStatus.UNAUTHORIZED);
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		res.write(Json.stringify({
			error: "Unauthorized",
			message: "Authentication required"
		}));
		res.end();
	}

	private function sendForbidden(res:Response, ?message:String):Void {
		res.sendResponse(snake.http.HTTPStatus.FORBIDDEN);
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		res.write(Json.stringify({
			error: "Forbidden",
			message: message ?? "Access denied"
		}));
		res.end();
	}
}
