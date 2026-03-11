# Authentication Middleware with OAuth Support

This guide explains how to use the authentication middleware with OAuth support in SideWinder.

## Overview

The authentication system provides:
- **OAuth Support**: Integration with multiple OAuth providers (Google, GitHub, Microsoft, custom)
- **Authentication Middleware**: Protect routes and validate tokens
- **Session Management**: Automatic session creation and validation
- **Token-based Auth**: Bearer token support and cookie-based sessions

## Components

### Core Interfaces & Services

1. **IOAuthService** (`IOAuthService.hx`)
   - Handles OAuth flow with external providers
   - Manages token exchange and user info retrieval

2. **IAuthService** (`IAuthService.hx`)
   - Session and token management
   - User authentication and OAuth coordination

3. **AuthService** (`AuthService.hx`)
   - Implementation of IAuthService
   - Manages in-memory sessions and tokens
   - Can be extended for persistent storage

4. **OAuthService** (`OAuthService.hx`)
   - Implementation of IOAuthService
   - Handles provider-specific OAuth flows

5. **AuthMiddleware** (`AuthMiddleware.hx`)
   - Express-like middleware for route protection
   - Validates tokens and manages auth context

6. **OAuthController** (`OAuthController.hx`)
   - HTTP endpoints for OAuth flow
   - Handles authorization, callbacks, and user info

## Setup

### 1. Configure Environment Variables

Create a `.env` file or set these environment variables:

```bash
# Google OAuth (optional)
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
GOOGLE_REDIRECT_URI=http://localhost:8000/oauth/callback/google

# GitHub OAuth (optional)
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
GITHUB_REDIRECT_URI=http://localhost:8000/oauth/callback/github

# Microsoft OAuth (optional)
MICROSOFT_CLIENT_ID=your_microsoft_client_id
MICROSOFT_CLIENT_SECRET=your_microsoft_client_secret
MICROSOFT_REDIRECT_URI=http://localhost:8000/oauth/callback/microsoft
```

### 2. Initialize in Main.hx

```haxe
// In your Main.hx or app initialization

import hx.injection.ServiceCollection;
import sidewinder.*;

class Main {
    public static function main() {
        var collection = new ServiceCollection();
        
        // Register UserService
        collection.addSingleton(new UserService(), IUserService);
        
        // Create and register AuthService
        var userService = new UserService();
        var authService = new AuthService(userService);
        collection.addSingleton(authService, IAuthService);
        
        // Register OAuth providers
        OAuthConfigSetup.setupGoogleOAuth(collection);
        OAuthConfigSetup.setupGitHubOAuth(collection);
        OAuthConfigSetup.setupMicrosoftOAuth(collection);
        
        // Initialize DI
        DI.init(function(c) {
            // ... other services
        });
        
        // Start your HTTP server...
    }
}
```

### 3. Set Up Routes

```haxe
import sidewinder.*;

class AppRoutes {
    public static function setup() {
        var authService = DI.get(IAuthService);
        var authMiddleware = new AuthMiddleware(authService);
        var oauthController = new OAuthController(authService);
        
        // OAuth endpoints (public)
        App.get("/oauth/authorize/:provider", 
            (req, res) -> oauthController.authorize(req, res));
        
        App.get("/oauth/callback/:provider", 
            (req, res) -> oauthController.callback(req, res));
        
        App.get("/oauth/logout", 
            (req, res) -> oauthController.logout(req, res));
        
        App.get("/oauth/user", 
            (req, res) -> oauthController.getCurrentUser(req, res));
        
        App.post("/oauth/refresh", 
            (req, res) -> oauthController.refreshSession(req, res));
        
        // Protected endpoints - require authentication
        App.use(authMiddleware.protect(["google", "github", "microsoft"]));
        
        App.get("/api/protected-resource", function(req:Request, res:Response) {
            var authContext = AuthMiddleware.getAuthContext(req);
            
            res.sendResponse(snake.http.HTTPStatus.OK);
            res.setHeader("Content-Type", "application/json");
            res.endHeaders();
            res.write(haxe.Json.stringify({
                message: "Protected resource",
                userId: authContext.userId,
                provider: authContext.session.provider
            }));
            res.end();
        });
        
        // Routes with optional authentication
        App.use(authMiddleware.optional());
        
        App.get("/api/public-with-optional-auth", function(req:Request, res:Response) {
            var authContext = AuthMiddleware.getAuthContext(req);
            
            var content:Dynamic = {
                message: "This resource is accessible to everyone"
            };
            
            if (authContext != null && authContext.authenticated) {
                content.user = {
                    userId: authContext.userId,
                    provider: authContext.session.provider
                };
            }
            
            res.sendResponse(snake.http.HTTPStatus.OK);
            res.setHeader("Content-Type", "application/json");
            res.endHeaders();
            res.write(haxe.Json.stringify(content));
            res.end();
        });
    }
}
```

## Usage Examples

### 1. OAuth Authorization Flow (Client-side)

```html
<!-- Frontend: Redirect user to authorization -->
<a href="/oauth/authorize/google">Login with Google</a>
<a href="/oauth/authorize/github">Login with GitHub</a>
<a href="/oauth/authorize/microsoft">Login with Microsoft</a>
```

After the user authenticates with the provider, they're redirected to `/oauth/callback/:provider`, which sets a cookie and returns a session token.

### 2. Using Bearer Tokens

```javascript
// After login, store the token
const token = response.token;

// Use it in API requests
fetch('/api/protected-resource', {
    headers: {
        'Authorization': `Bearer ${token}`
    }
})
.then(r => r.json())
.then(data => console.log(data));
```

### 3. Using Cookies

```javascript
// The auth middleware automatically sets `auth_token` cookie
// Subsequent requests will automatically include it

fetch('/api/protected-resource')
    .then(r => r.json())
    .then(data => console.log(data));
```

### 4. Get Current User Info

```javascript
fetch('/oauth/user')
    .then(r => r.json())
    .then(data => {
        console.log('Current user:', data);
    });
```

### 5. Logout

```javascript
fetch('/oauth/logout', { method: 'GET' })
    .then(r => r.json())
    .then(data => {
        // User is logged out, auth_token cookie is cleared
        console.log(data.message);
    });
```

### 6. Refresh Session

```javascript
fetch('/oauth/refresh', { method: 'POST' })
    .then(r => r.json())
    .then(data => {
        // New token in response
        const newToken = data.token;
        console.log('Session refreshed');
    });
```

## Advanced Usage

### Custom OAuth Provider

```haxe
var customConfig:IOAuthService.OAuthConfig = {
    clientId: "your_client_id",
    clientSecret: "your_client_secret",
    redirectUri: "http://localhost:8000/oauth/callback/custom",
    scope: "openid profile email",
    authorizationEndpoint: "https://custom-provider.com/oauth2/authorize",
    tokenEndpoint: "https://custom-provider.com/oauth2/token",
    userInfoEndpoint: "https://custom-provider.com/oauth2/userinfo",
    provider: "custom"
};

var collection = new ServiceCollection();
OAuthConfigSetup.setupCustomOAuth(collection, customConfig);
```

### Protected Routes with Specific Providers

```haxe
// Only allow GitHub and Google users
App.use(authMiddleware.protect(["github", "google"]));

App.get("/api/admin", function(req:Request, res:Response) {
    // Only authenticated GitHub or Google users can access
    // ...
});
```

### Checking Authentication in Handlers

```haxe
App.get("/api/user-profile", function(req:Request, res:Response) {
    var authContext = AuthMiddleware.getAuthContext(req);
    
    if (authContext == null || !authContext.authenticated) {
        res.sendResponse(snake.http.HTTPStatus.UNAUTHORIZED);
        res.setHeader("Content-Type", "application/json");
        res.endHeaders();
        res.write(haxe.Json.stringify({
            error: "Not authenticated"
        }));
        res.end();
        return;
    }
    
    var userId = authContext.userId;
    var provider = authContext.session.provider;
    
    // Use userId to fetch user data
    // ...
});
```

## Database Integration (Recommended)

The current `AuthService` uses in-memory storage. For production, you should persist sessions and tokens:

```haxe
// Extend AuthService to add database storage
class PersistentAuthService extends AuthService {
    override public function createSession(userId:Int, provider:String):AuthSession {
        var session = super.createSession(userId, provider);
        
        // Save to database
        var params = new Map<String, Dynamic>();
        params.set("session_id", session.sessionId);
        params.set("user_id", userId);
        params.set("token", session.token.token);
        params.set("provider", provider);
        params.set("expires_at", session.expiresAt.toString());
        
        Database.requestWithParams(
            "INSERT INTO auth_sessions (session_id, user_id, token, provider, expires_at) 
             VALUES (@session_id, @user_id, @token, @provider, @expires_at)",
            params
        );
        
        return session;
    }
    
    override public function validateToken(token:String):Null<AuthSession> {
        // Check database first
        var params = new Map<String, Dynamic>();
        params.set("token", token);
        
        var rs = Database.requestWithParams(
            "SELECT * FROM auth_sessions WHERE token = @token AND expires_at > datetime('now')",
            params
        );
        
        var row = rs.next();
        if (row != null) {
            // Return session from database
            // ...
        }
        
        return super.validateToken(token);
    }
}
```

## API Endpoints Reference

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---|
| GET | `/oauth/authorize/:provider` | Redirect to OAuth provider | No |
| GET | `/oauth/callback/:provider` | OAuth callback endpoint | No |
| GET | `/oauth/logout` | Logout user | Yes |
| GET | `/oauth/user` | Get current user info | Yes |
| POST | `/oauth/refresh` | Refresh session | Yes |

## Security Considerations

1. **HTTPS in Production**: Always use HTTPS in production
2. **PKCE**: Consider enabling PKCE for public clients
3. **State Verification**: CSRF protection via state parameter
4. **Token Expiry**: Tokens expire after 24 hours
5. **HttpOnly Cookies**: Auth cookies are HttpOnly by default
6. **Secure Flag**: Set `secure: true` in production (requires HTTPS)
7. **Persistent Storage**: Use database for production session storage

## Troubleshooting

### "OAuth provider not registered"
- Make sure you called the appropriate setup function (e.g., `OAuthConfigSetup.setupGoogleOAuth()`)
- Verify environment variables are set correctly

### "Invalid or expired state"
- State expires after 5 minutes
- Clear browser cookies and retry

### "Unauthorized" on protected routes
- Check that `Authorization` header or `auth_token` cookie is present
- Token may have expired (24-hour expiry)
- Call `/oauth/refresh` to get a new token

### Token not being sent
- Make sure to include `Authorization: Bearer <token>` header in requests
- Or enable cookies in your HTTP client

## License

Part of the SideWinder HTTP framework.
