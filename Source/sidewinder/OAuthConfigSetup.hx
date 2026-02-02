package sidewinder;

import hx.injection.ServiceCollection;

/**
 * OAuth Configuration and Setup
 * This class provides helper methods to configure OAuth providers in the DI container
 */
class OAuthConfig {
	/**
	 * Configure OAuth services in the DI container
	 * 
	 * Example usage:
	 * ```
	 * var collection = new ServiceCollection();
	 * OAuthConfig.setupGoogleOAuth(collection);
	 * OAuthConfig.setupGitHubOAuth(collection);
	 * OAuthConfig.setupMicrosoftOAuth(collection);
	 * ```
	 */

	/**
	 * Setup Google OAuth provider
	 * Requires environment variables:
	 * - GOOGLE_CLIENT_ID
	 * - GOOGLE_CLIENT_SECRET
	 * - GOOGLE_REDIRECT_URI (default: http://localhost:8000/oauth/callback/google)
	 */
	public static function setupGoogleOAuth(collection:ServiceCollection):Void {
		var clientId = Sys.getEnv("GOOGLE_CLIENT_ID") ?? "";
		var clientSecret = Sys.getEnv("GOOGLE_CLIENT_SECRET") ?? "";
		var redirectUri = Sys.getEnv("GOOGLE_REDIRECT_URI") ?? "http://localhost:8000/oauth/callback/google";

		var config:IOAuthService.OAuthConfig = {
			clientId: clientId,
			clientSecret: clientSecret,
			redirectUri: redirectUri,
			scope: "openid profile email",
			authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
			tokenEndpoint: "https://oauth2.googleapis.com/token",
			userInfoEndpoint: "https://openidconnect.googleapis.com/v1/userinfo",
			provider: "google"
		};

		collection.addSingleton(new OAuthService(config), IOAuthService, "google");
	}

	/**
	 * Setup GitHub OAuth provider
	 * Requires environment variables:
	 * - GITHUB_CLIENT_ID
	 * - GITHUB_CLIENT_SECRET
	 * - GITHUB_REDIRECT_URI (default: http://localhost:8000/oauth/callback/github)
	 */
	public static function setupGitHubOAuth(collection:ServiceCollection):Void {
		var clientId = Sys.getEnv("GITHUB_CLIENT_ID") ?? "";
		var clientSecret = Sys.getEnv("GITHUB_CLIENT_SECRET") ?? "";
		var redirectUri = Sys.getEnv("GITHUB_REDIRECT_URI") ?? "http://localhost:8000/oauth/callback/github";

		var config:IOAuthService.OAuthConfig = {
			clientId: clientId,
			clientSecret: clientSecret,
			redirectUri: redirectUri,
			scope: "user:email",
			authorizationEndpoint: "https://github.com/login/oauth/authorize",
			tokenEndpoint: "https://github.com/login/oauth/access_token",
			userInfoEndpoint: "https://api.github.com/user",
			provider: "github"
		};

		collection.addSingleton(new OAuthService(config), IOAuthService, "github");
	}

	/**
	 * Setup Microsoft OAuth provider
	 * Requires environment variables:
	 * - MICROSOFT_CLIENT_ID
	 * - MICROSOFT_CLIENT_SECRET
	 * - MICROSOFT_REDIRECT_URI (default: http://localhost:8000/oauth/callback/microsoft)
	 */
	public static function setupMicrosoftOAuth(collection:ServiceCollection):Void {
		var clientId = Sys.getEnv("MICROSOFT_CLIENT_ID") ?? "";
		var clientSecret = Sys.getEnv("MICROSOFT_CLIENT_SECRET") ?? "";
		var redirectUri = Sys.getEnv("MICROSOFT_REDIRECT_URI") ?? "http://localhost:8000/oauth/callback/microsoft";

		var config:IOAuthService.OAuthConfig = {
			clientId: clientId,
			clientSecret: clientSecret,
			redirectUri: redirectUri,
			scope: "openid profile email",
			authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
			tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
			userInfoEndpoint: "https://graph.microsoft.com/v1.0/me",
			provider: "microsoft"
		};

		collection.addSingleton(new OAuthService(config), IOAuthService, "microsoft");
	}

	/**
	 * Setup a custom OAuth provider
	 */
	public static function setupCustomOAuth(collection:ServiceCollection, config:IOAuthService.OAuthConfig):Void {
		collection.addSingleton(new OAuthService(config), IOAuthService, config.provider);
	}
}
