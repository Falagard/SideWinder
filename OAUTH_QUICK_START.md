# OAuth Authentication - Quick Reference

## Quick Start (5 Minutes)

### 1. Add to Main.hx
```haxe
var authService = new AuthService(userService);
var collection = new ServiceCollection();
collection.addSingleton(authService, IAuthService);
OAuthConfigSetup.setupGoogleOAuth(collection);
OAuthConfigSetup.setupGitHubOAuth(collection);
DI.init(function(c) { /* ... */ });
```

### 2. Add Routes
```haxe
var authService = DI.get(IAuthService);
var authMiddleware = new AuthMiddleware(authService);
var oauthController = new OAuthController(authService);

App.get("/oauth/authorize/:provider", (req, res) -> oauthController.authorize(req, res));
App.get("/oauth/callback/:provider", (req, res) -> oauthController.callback(req, res));
App.use(authMiddleware.protect());
App.get("/api/protected", myHandler);
```

### 3. Use in Handlers
```haxe
App.get("/api/profile", function(req:Request, res:Response) {
    if (!AuthUtils.requireAuth(req, res)) return;
    var userId = AuthUtils.getUserId(req);
    // ... rest of handler
});
```

---

## Common Tasks

### Protect a Route
```haxe
App.use(authMiddleware.protect());
App.get("/api/resource", handler);
```

### Allow Only Specific Provider
```haxe
App.use(authMiddleware.protect(["google", "github"]));
App.get("/api/admin", handler);
```

### Optional Authentication
```haxe
App.use(authMiddleware.optional());
App.get("/api/public", handler);
```

### Check Auth in Handler
```haxe
if (AuthUtils.isAuthenticated(req)) {
    var userId = AuthUtils.getUserId(req);
    var provider = AuthUtils.getProvider(req);
}
```

### Require Auth or Fail
```haxe
if (!AuthUtils.requireAuth(req, res)) return;
// Continue with authenticated handler
```

### Require Specific Provider
```haxe
if (!AuthUtils.requireProvider(req, res, "google")) return;
```

### Own Resource Protection
```haxe
if (!AuthUtils.requireOwnResource(req, res, targetUserId)) return;
```

---

## Frontend Integration

### Login Button
```html
<a href="/oauth/authorize/google">Login with Google</a>
<a href="/oauth/authorize/github">Login with GitHub</a>
```

### After Login
```javascript
// The token will be in the auth_token cookie
// OR check the response from /oauth/callback/:provider

// Make authenticated requests
fetch('/api/profile', {
    headers: { 'Authorization': `Bearer ${token}` }
})
```

### Get Current User
```javascript
fetch('/oauth/user', {
    headers: { 'Authorization': `Bearer ${token}` }
})
.then(r => r.json())
.then(user => console.log(user))
```

### Logout
```javascript
fetch('/oauth/logout')
.then(r => r.json())
.then(result => window.location = '/')
```

### Refresh Token
```javascript
fetch('/oauth/refresh', { method: 'POST' })
.then(r => r.json())
.then(data => {
    const newToken = data.token
    localStorage.setItem('token', newToken)
})
```

---

## Environment Variables

```bash
# Google
GOOGLE_CLIENT_ID=123456.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=secret
GOOGLE_REDIRECT_URI=http://localhost:8000/oauth/callback/google

# GitHub
GITHUB_CLIENT_ID=abc123
GITHUB_CLIENT_SECRET=secret
GITHUB_REDIRECT_URI=http://localhost:8000/oauth/callback/github

# Microsoft
MICROSOFT_CLIENT_ID=uuid
MICROSOFT_CLIENT_SECRET=secret
MICROSOFT_REDIRECT_URI=http://localhost:8000/oauth/callback/microsoft
```

---

## File Structure

```
Source/sidewinder/
├── IOAuthService.hx           # OAuth service interface
├── IAuthService.hx            # Auth service interface
├── OAuthService.hx            # OAuth implementation
├── AuthService.hx             # Auth implementation
├── OAuthConfigSetup.hx        # Provider setup helpers
├── AuthMiddleware.hx          # Route protection middleware
├── OAuthController.hx         # HTTP endpoints
├── AuthUtils.hx               # Helper functions
└── ExampleAuthApp.hx          # Example routes
```

---

## API Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/oauth/authorize/:provider` | GET | - | Redirect to provider |
| `/oauth/callback/:provider` | GET | - | Provider callback |
| `/oauth/user` | GET | ✓ | Get current user |
| `/oauth/logout` | GET | ✓ | Logout user |
| `/oauth/refresh` | POST | ✓ | Refresh session |

---

## Common Patterns

### Require Admin (Specific Provider)
```haxe
App.use(authMiddleware.protect(["github"]));
App.get("/admin", handler);
```

### Public API with Optional Auth
```haxe
App.use(authMiddleware.optional());
App.get("/api/posts", function(req, res) {
    var userId = AuthUtils.getUserId(req);
    if (userId != null) {
        // Authenticated request
    } else {
        // Unauthenticated request
    }
});
```

### User-Specific Resource
```haxe
App.get("/api/users/:userId/profile", function(req, res) {
    var targetUserId = Std.parseInt(req.params.get("userId"));
    if (!AuthUtils.requireOwnResource(req, res, targetUserId)) return;
    // Safe to fetch user data
});
```

### Check Token Expiry
```haxe
var authContext = AuthMiddleware.getAuthContext(req);
if (AuthUtils.isTokenExpiringSoon(authContext.token)) {
    // Suggest refresh to frontend
}
```

---

## Troubleshooting

### 401 Unauthorized
- Check Authorization header is present and correct
- Token may have expired (24-hour limit)
- Check browser cookies for `auth_token`

### 403 Forbidden
- Provider not allowed for this route
- Check which providers are required

### CORS Issues
- Enable CORS headers in SideWinderServer
- Check frontend domain in OAuth redirect URI

### "Provider not registered"
- Make sure `OAuthConfigSetup.setupXxxOAuth()` was called
- Check environment variables are set

### Token not in cookie
- Make sure browser allows cookies
- Check if API is on same domain
- HTTPS required in production for secure flag

---

## Security Checklist

- [ ] Environment variables set (never hardcode credentials)
- [ ] HTTPS enabled in production
- [ ] Secure flag enabled for cookies in production
- [ ] HttpOnly flag enabled for cookies (default)
- [ ] CSRF state validation working
- [ ] Rate limiting on OAuth endpoints
- [ ] Invalid tokens rejected
- [ ] Expired tokens not accepted
- [ ] User data not exposed in auth responses
- [ ] Sensitive fields logged appropriately

---

## Next Steps

1. Set environment variables for OAuth providers
2. Call `OAuthConfigSetup.setupXxxOAuth()` for each provider
3. Register auth routes with `App.get()` and `App.use()`
4. Add `AuthUtils.requireAuth()` checks to protected handlers
5. Test with Postman or curl
6. Implement frontend login flow
7. Add rate limiting middleware
8. Set up database persistence

See `AUTH_README.md` for detailed guide.
See `OAUTH_API.md` for API reference.
