package sidewinder.controllers;

import sidewinder.interfaces.IAuthService;
import sidewinder.interfaces.INotificationService;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;
import sidewinder.logging.HybridLogger;
import snake.http.HTTPStatus;
import haxe.Json;

class MagicLinkController {
	private var authService:IAuthService;
	private var notificationService:INotificationService;

	public function new(authService:IAuthService, notificationService:INotificationService) {
		this.authService = authService;
		this.notificationService = notificationService;
	}

	/**
	 * POST /auth/magic-link
	 * Request a new magic link
	 */
	public function requestLink(req:Request, res:Response):Void {
		var email = Reflect.field(req.jsonBody, "email");
		
		if (email == null || email == "") {
			sendJsonError(res, HTTPStatus.BAD_REQUEST, "Email is required");
			return;
		}

		try {
			var token = authService.requestMagicLink(email);
			
			// Build the verification URL
			// In production, you would use an environment variable for the base URL
			var baseUrl = "http://localhost:8001"; // Consistent with current dev port
			var verifyUrl = '$baseUrl/auth/magic-link/verify?token=' + StringTools.urlEncode(token);
			
			// Construct email body
			var subject = "Your Magic Login Link";
			var body = 'Hello!\n\nPlease click the following link to log in to your account:\n\n$verifyUrl\n\nThis link will expire in 15 minutes.';
			
			// Send the email (fire-and-forget for the controller, but async in background)
			if (notificationService != null) {
				notificationService.sendEmail(email, subject, body, false, function(err) {
					if (err != null) {
						HybridLogger.error('Failed to send magic link email to $email: $err');
					} else {
						HybridLogger.info('Sent magic link email to $email');
					}
				});
			} else {
				HybridLogger.warn('[DEV MODE] Magic link generated but NOT sent: $verifyUrl');
			}

			// We always return success immediately to prevent email enumeration attacks
			res.sendResponse(HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			res.endHeaders();
			try {
				res.write(Json.stringify({
					success: true,
					message: "If that email exists in our system, a magic link has been sent."
				}));
				res.end();
			} catch (e:Dynamic) {}
			
		} catch (e:Dynamic) {
			HybridLogger.error('Error requesting magic link: $e');
			sendJsonError(res, HTTPStatus.INTERNAL_SERVER_ERROR, "Failed to process magic link request");
		}
	}

	/**
	 * GET /auth/magic-link/verify
	 * Verify a magic link and log the user in
	 */
	public function verifyLink(req:Request, res:Response):Void {
		HybridLogger.debug('[MagicLinkController] Verifying token. Query params: ' + [for (k in req.query.keys()) '$k=${req.query.get(k)}'].join(", "));
		var token = req.query.get("token");
		
		if (token == null || token == "") {
			sendJsonError(res, HTTPStatus.BAD_REQUEST, "Token is required");
			return;
		}

		try {
			var session = authService.authenticateWithMagicLink(token);
			
			res.sendResponse(HTTPStatus.OK);
			res.setHeader("Content-Type", "application/json");
			
			// Set the auth token cookie exactly like OAuthController does
			res.setCookie("auth_token", session.token.token, {
				path: "/",
				httpOnly: true,
				secure: false, // Set to true in production with HTTPS
				maxAge: Std.string(24 * 60 * 60) // 24 hours
			});
			
			
			res.endHeaders();
			try {
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
			} catch (e:Dynamic) {}
			
		} catch (e:Dynamic) {
			HybridLogger.error('Failed magic link verification: $e');
			sendJsonError(res, HTTPStatus.UNAUTHORIZED, Std.string(e)); // Send 401 for invalid/expired tokens
		}
	}

	private function sendJsonError(res:Response, status:HTTPStatus, message:String):Void {
		res.sendResponse(status);
		res.setHeader("Content-Type", "application/json");
		res.endHeaders();
		try {
			res.write(Json.stringify({
				error: message
			}));
			res.end();
		} catch (e:Dynamic) {}
	}
}
