package sidewinder.data;

import sidewinder.interfaces.IOAuthService;
import sidewinder.services.OAuthService;
import hx.injection.ServiceCollection;

using hx.injection.ServiceExtensions;

/**
 * OAuth Configuration and Setup
 * This class provides helper methods to configure OAuth providers.
 */
class OAuthConfigSetup {
	/**
	 * Setup Google OAuth provider
	 */
	public static function setupGoogleOAuth(collection:ServiceCollection):Void {
		var clientId = Sys.getEnv("GOOGLE_CLIENT_ID");
		if (clientId == null) clientId = "";
		var clientSecret = Sys.getEnv("GOOGLE_CLIENT_SECRET");
		if (clientSecret == null) clientSecret = "";
		var redirectUri = Sys.getEnv("GOOGLE_REDIRECT_URI");
		if (redirectUri == null) redirectUri = "http://localhost:8000/oauth/callback/google";

		var config = new sidewinder.interfaces.IOAuthService.OAuthConfig();
		config.clientId = clientId;
		config.clientSecret = clientSecret;
		config.redirectUri = redirectUri;
		config.scope = "openid profile email";
		config.authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth";
		config.tokenEndpoint = "https://oauth2.googleapis.com/token";
		config.userInfoEndpoint = "https://openidconnect.googleapis.com/v1/userinfo";
		config.provider = "google";

		// Mapping for instances with bindings is not directly supported by hx-injection ServiceCollection
		// collection.addService(IOAuthService, new OAuthService(config));
	}

	/**
	 * Setup GitHub OAuth provider
	 */
	public static function setupGitHubOAuth(collection:ServiceCollection):Void {
		var clientId = Sys.getEnv("GITHUB_CLIENT_ID");
		if (clientId == null) clientId = "";
		var clientSecret = Sys.getEnv("GITHUB_CLIENT_SECRET");
		if (clientSecret == null) clientSecret = "";
		var redirectUri = Sys.getEnv("GITHUB_REDIRECT_URI");
		if (redirectUri == null) redirectUri = "http://localhost:8000/oauth/callback/github";

		var config = new sidewinder.interfaces.IOAuthService.OAuthConfig();
		config.clientId = clientId;
		config.clientSecret = clientSecret;
		config.redirectUri = redirectUri;
		config.scope = "user:email";
		config.authorizationEndpoint = "https://github.com/login/oauth/authorize";
		config.tokenEndpoint = "https://github.com/login/oauth/access_token";
		config.userInfoEndpoint = "https://api.github.com/user";
		config.provider = "github";

		// collection.addService(IOAuthService, new OAuthService(config));
	}

	/**
	 * Setup Microsoft OAuth provider
	 */
	public static function setupMicrosoftOAuth(collection:ServiceCollection):Void {
		var clientId = Sys.getEnv("MICROSOFT_CLIENT_ID");
		if (clientId == null) clientId = "";
		var clientSecret = Sys.getEnv("MICROSOFT_CLIENT_SECRET");
		if (clientSecret == null) clientSecret = "";
		var redirectUri = Sys.getEnv("MICROSOFT_REDIRECT_URI");
		if (redirectUri == null) redirectUri = "http://localhost:8000/oauth/callback/microsoft";

		var config = new sidewinder.interfaces.IOAuthService.OAuthConfig();
		config.clientId = clientId;
		config.clientSecret = clientSecret;
		config.redirectUri = redirectUri;
		config.scope = "openid profile email";
		config.authorizationEndpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
		config.tokenEndpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
		config.userInfoEndpoint = "https://graph.microsoft.com/v1.0/me";
		config.provider = "microsoft";

		// collection.addService(IOAuthService, new OAuthService(config));
	}
}
