# OAuth Authentication - Reference Card

## File Locations

```
Source/sidewinder/
├── IOAuthService.hx          Interfaces
├── IAuthService.hx           (2 files)
├── OAuthService.hx           Implementations
├── AuthService.hx            (2 files)
├── AuthMiddleware.hx         Middleware
├── OAuthController.hx        (2 files)
├── AuthUtils.hx              Utilities
├── OAuthConfigSetup.hx       (2 files)
├── ExampleAuthApp.hx         Examples
└── Router.hx                 (UPDATED)

Documentation/
├── AUTH_README.md
├── OAUTH_QUICK_START.md
├── OAUTH_API.md
├── OAUTH_ARCHITECTURE.md
├── OAUTH_IMPLEMENTATION.md
└── OAUTH_COMPLETE_SUMMARY.md
```

## Most Common Code Patterns

### Initialize Services
```haxe
var authService = new AuthService(userService);
var authMiddleware = new AuthMiddleware(authService);
var oauthController = new OAuthController(authService);

OAuthConfigSetup.setupGoogleOAuth(collection);
OAuthConfigSetup.setupGitHubOAuth(collection);

collection.addSingleton(authService, IAuthService);
```

### Protect a Route
```haxe
// Require authentication
App.use(authMiddleware.protect());
App.get("/api/protected", handler);

// Optional authentication
App.use(authMiddleware.optional());
App.get("/api/public", handler);

// Specific provider
App.use(authMiddleware.protect(["google", "github"]));
App.get("/api/admin", handler);
```

### Check Auth in Handler
```haxe
if (!AuthUtils.requireAuth(req, res)) return;
if (!AuthUtils.requireProvider(req, res, "google")) return;
if (!AuthUtils.requireOwnResource(req, res, userId)) return;

var userId = AuthUtils.getUserId(req);
var provider = AuthUtils.getProvider(req);
var isAuth = AuthUtils.isAuthenticated(req);
```

### Set Up OAuth Endpoints
```haxe
App.get("/oauth/authorize/:provider", 
  (req, res) -> oauthController.authorize(req, res));
App.get("/oauth/callback/:provider", 
  (req, res) -> oauthController.callback(req, res));
App.get("/oauth/user", 
  (req, res) -> oauthController.getCurrentUser(req, res));
App.get("/oauth/logout", 
  (req, res) -> oauthController.logout(req, res));
App.post("/oauth/refresh", 
  (req, res) -> oauthController.refreshSession(req, res));
```

## API Endpoints

| Path | Method | Auth | Returns |
|------|--------|------|---------|
| `/oauth/authorize/:provider` | GET | - | 302 redirect |
| `/oauth/callback/:provider` | GET | - | Session JSON |
| `/oauth/user` | GET | ✓ | User info JSON |
| `/oauth/logout` | GET | ✓ | Success JSON |
| `/oauth/refresh` | POST | ✓ | New session JSON |

## Environment Variables

```bash
# Google OAuth
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxx
GOOGLE_REDIRECT_URI=http://localhost:8000/oauth/callback/google

# GitHub OAuth
GITHUB_CLIENT_ID=xxx
GITHUB_CLIENT_SECRET=xxx
GITHUB_REDIRECT_URI=http://localhost:8000/oauth/callback/github

# Microsoft OAuth
MICROSOFT_CLIENT_ID=xxx
MICROSOFT_CLIENT_SECRET=xxx
MICROSOFT_REDIRECT_URI=http://localhost:8000/oauth/callback/microsoft
```

## Frontend Integration

```html
<!-- Login Links -->
<a href="/oauth/authorize/google">Login with Google</a>
<a href="/oauth/authorize/github">Login with GitHub</a>
```

```javascript
// Make authenticated request
fetch('/api/profile', {
  headers: { 'Authorization': `Bearer ${token}` }
})
.then(r => r.json())
.then(user => console.log(user))

// Get current user
fetch('/oauth/user', {
  headers: { 'Authorization': `Bearer ${token}` }
})

// Refresh session
fetch('/oauth/refresh', { method: 'POST' })
  .then(r => r.json())
  .then(data => localStorage.setItem('token', data.token))

// Logout
fetch('/oauth/logout')
  .then(r => r.json())
  .then(() => window.location = '/')
```

## TypeDefs

```haxe
// OAuth Configuration
typedef OAuthConfig = {
  clientId:String,
  clientSecret:String,
  redirectUri:String,
  scope:String,
  authorizationEndpoint:String,
  tokenEndpoint:String,
  userInfoEndpoint:String,
  provider:String
}

// OAuth Token
typedef OAuthToken = {
  accessToken:String,
  refreshToken:Null<String>,
  expiresIn:Int,
  tokenType:String,
  createdAt:Date
}

// Auth Token
typedef AuthToken = {
  token:String,
  userId:Int,
  expiresAt:Date,
  createdAt:Date
}

// Auth Session
typedef AuthSession = {
  sessionId:String,
  userId:Int,
  token:AuthToken,
  provider:String,
  expiresAt:Date
}

// Auth Context
typedef AuthContext = {
  authenticated:Bool,
  userId:Null<Int>,
  session:Null<AuthSession>,
  token:Null<String>
}
```

## Key Methods

### AuthService
- `registerOAuthProvider(provider:String, service:IOAuthService)`
- `authenticateWithOAuth(code:String, provider:String):AuthSession`
- `createOrUpdateUserFromOAuth(oauthUser:OAuthUserInfo):Int`
- `createSession(userId:Int, provider:String):AuthSession`
- `validateToken(token:String):Null<AuthSession>`
- `revokeSession(sessionId:String):Bool`
- `refreshSession(sessionId:String):Null<AuthSession>`

### OAuthService
- `getAuthorizationUrl(state:String):String`
- `exchangeCodeForToken(code:String):OAuthToken`
- `refreshAccessToken(refreshToken:String):OAuthToken`
- `getUserInfo(accessToken:String):OAuthUserInfo`

### AuthMiddleware
- `create(requiredAuth:Bool):Middleware`
- `protect(allowedProviders:Array<String>):Middleware`
- `optional():Middleware`
- `static getAuthContext(req:Request):Null<AuthContext>`

### OAuthController
- `authorize(req:Request, res:Response)`
- `callback(req:Request, res:Response)`
- `logout(req:Request, res:Response)`
- `getCurrentUser(req:Request, res:Response)`
- `refreshSession(req:Request, res:Response)`

### AuthUtils
- `extractToken(req:Request):Null<String>`
- `isAuthenticated(req:Request):Bool`
- `getUserId(req:Request):Null<Int>`
- `getProvider(req:Request):Null<String>`
- `requireAuth(req:Request, res:Response):Bool`
- `requireProvider(req:Request, res:Response, provider:String):Bool`
- `requireAnyProvider(req:Request, res:Response, providers:Array<String>):Bool`
- `requireOwnResource(req:Request, res:Response, userId:Int):Bool`
- `generateState():String`
- `generatePkceVerifier():String`
- `generatePkceChallenge(verifier:String):String`
- `sendJson(res:Response, status:Int, data:Dynamic):Void`
- `getTimeUntilExpiry(token:AuthToken):Int`
- `isTokenExpiringSoon(token:AuthToken):Bool`

## Error Responses

```json
// 401 Unauthorized
{ "error": "Unauthorized", "message": "Authentication required" }

// 403 Forbidden
{ "error": "Forbidden", "message": "Access denied" }

// 400 Bad Request
{ "error": "OAuth error: invalid_request", "message": "..." }

// 500 Server Error
{ "error": "OAuth error: Failed to exchange code for token" }
```

## Success Responses

```json
// Callback response
{
  "success": true,
  "session": {
    "sessionId": "...",
    "userId": 42,
    "provider": "google",
    "expiresAt": "2026-02-02T00:00:00Z"
  },
  "token": "eyJhbGciOi..."
}

// User info response
{
  "userId": 42,
  "provider": "google",
  "expiresAt": "2026-02-02T00:00:00Z"
}

// Logout response
{
  "success": true,
  "message": "Logged out successfully"
}
```

## Common Errors & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| "OAuth provider not registered" | Provider setup missing | Call `OAuthConfigSetup.setupXxxOAuth()` |
| "Invalid or expired state" | CSRF protection failed | Clear cookies and retry |
| 401 Unauthorized | Missing token | Check Authorization header |
| 403 Forbidden | Wrong provider | Provider not in allowed list |
| CORS error | Browser security | Configure CORS in server |
| Token not in cookie | Session issue | Check domain and HTTPS |

## Documentation Reference

| File | Purpose | When to Use |
|------|---------|-----------|
| OAUTH_QUICK_START.md | Quick reference | Getting started |
| AUTH_README.md | Complete guide | Setup and configuration |
| OAUTH_API.md | API specification | API endpoint details |
| OAUTH_ARCHITECTURE.md | System design | Understanding architecture |
| OAUTH_IMPLEMENTATION.md | What was done | Implementation details |

## Security Checklist

- [ ] HTTPS enabled (production)
- [ ] Secure cookie flag set (production)
- [ ] Environment variables configured
- [ ] Rate limiting implemented
- [ ] CSRF validation working
- [ ] Token expiry enforced
- [ ] Invalid tokens rejected
- [ ] Expired tokens rejected
- [ ] User data not exposed
- [ ] Error messages safe
- [ ] Database persistence (if used)
- [ ] Audit logging (if needed)

## Performance Tips

1. **Cache OAuth config** - Don't regenerate on each request
2. **Cache user lookups** - Use ICacheService
3. **Async token refresh** - Don't block on HTTP calls
4. **Database indexes** - Index session IDs and tokens
5. **Token cleanup** - Implement expiry cleanup
6. **Connection pooling** - Pool database connections

## Testing Commands

```bash
# Test authorization URL
curl "http://localhost:8000/oauth/authorize/google"

# Test protected endpoint (will fail without token)
curl "http://localhost:8000/api/profile"

# Test protected endpoint with token
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/profile"

# Test logout
curl "http://localhost:8000/oauth/logout"

# Test refresh
curl -X POST "http://localhost:8000/oauth/refresh" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Production Deployment

1. ✅ Use HTTPS everywhere
2. ✅ Set Secure flag on cookies
3. ✅ Configure environment variables
4. ✅ Enable rate limiting
5. ✅ Set up database persistence
6. ✅ Configure proper error handling
7. ✅ Enable audit logging
8. ✅ Set up monitoring
9. ✅ Regular security updates
10. ✅ Backup strategies

---

**For detailed information, see the complete documentation files.**
