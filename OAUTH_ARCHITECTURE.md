# OAuth Authentication Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend Browser                          │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ 1. Click "Login with Google"                              │ │
│  │    → Navigate to /oauth/authorize/google                  │ │
│  │                                                             │ │
│  │ 2. Redirected to Google Login                             │ │
│  │    → User authenticates with Google                       │ │
│  │                                                             │ │
│  │ 3. Google redirects back with authorization code          │ │
│  │    → /oauth/callback/google?code=...&state=...           │ │
│  │                                                             │ │
│  │ 4. Receive auth_token cookie & session info              │ │
│  │    → Store token in localStorage/sessionStorage           │ │
│  │                                                             │ │
│  │ 5. Make authenticated requests                            │ │
│  │    → Authorization: Bearer <token>                        │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                            ↑ ↓
┌─────────────────────────────────────────────────────────────────┐
│                   SideWinder Server                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Routing Layer                          │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │  Router.hx                                          │ │  │
│  │  │  - Route matching                                  │ │  │
│  │  │  - Middleware execution chain                      │ │  │
│  │  │  - Handler execution                               │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Authentication Middleware                   │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │  AuthMiddleware.hx                                 │ │  │
│  │  │  - Extract token from header/cookie                │ │  │
│  │  │  - Validate token                                  │ │  │
│  │  │  - Store auth context in request                  │ │  │
│  │  │  - Apply provider-specific protection             │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Authentication Services                     │  │
│  │  ┌──────────────────┐      ┌──────────────────────────┐ │  │
│  │  │ AuthService      │      │ OAuthService            │ │  │
│  │  │ (IAuthService)   │      │ (IOAuthService)         │ │  │
│  │  │                  │      │                          │ │  │
│  │  │ • Sessions       │      │ • Token exchange        │ │  │
│  │  │ • Tokens         │      │ • User info retrieval   │ │  │
│  │  │ • Validation     │      │ • Token refresh         │ │  │
│  │  │ • User linking   │      │ • PKCE support          │ │  │
│  │  └──────────────────┘      └──────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  HTTP Endpoints                          │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │  OAuthController.hx                                │ │  │
│  │  │  - GET  /oauth/authorize/:provider                │ │  │
│  │  │  - GET  /oauth/callback/:provider                 │ │  │
│  │  │  - GET  /oauth/logout                             │ │  │
│  │  │  - GET  /oauth/user                               │ │  │
│  │  │  - POST /oauth/refresh                            │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Utilities & Helpers                         │  │
│  │  ┌──────────────────────────────────────────────────────┐ │  │
│  │  │ AuthUtils.hx                                         │ │  │
│  │  │ • Token extraction         • Response formatting    │ │  │
│  │  │ • Auth checks              • Expiry checking         │ │  │
│  │  │ • PKCE generation          • JSON error responses    │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  │  ┌──────────────────────────────────────────────────────┐ │  │
│  │  │ OAuthConfigSetup.hx                                  │ │  │
│  │  │ • setupGoogleOAuth()       • setupCustomOAuth()      │ │  │
│  │  │ • setupGitHubOAuth()       • Environment config      │ │  │
│  │  │ • setupMicrosoftOAuth()                              │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            ↑ ↓
┌─────────────────────────────────────────────────────────────────┐
│                    OAuth Providers                              │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐│
│  │   Google OAuth  │  │   GitHub OAuth  │  │ Microsoft OAuth  ││
│  │                 │  │                 │  │                  ││
│  │ • accounts.     │  │ • github.com/   │  │ • login.         ││
│  │   google.com    │  │   login/oauth   │  │   microsofton    ││
│  │                 │  │                 │  │   line.com       ││
│  └─────────────────┘  └─────────────────┘  └──────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Component Interaction Flow

### OAuth Authorization Flow (First-time Login)

```
1. User clicks "Login with Google"
   └─→ Frontend: GET /oauth/authorize/google

2. AuthMiddleware receives request
   └─→ Extracts authorization URL parameters
   └─→ Generates CSRF state token
   └─→ Optionally generates PKCE challenge

3. OAuthController.authorize()
   └─→ Constructs OAuth authorization URL
   └─→ Caches state for later verification
   └─→ HTTP 302 redirect to Google

4. Google OAuth
   └─→ User sees Google login screen
   └─→ User authenticates and grants permissions
   └─→ Google redirects to /oauth/callback/google?code=...&state=...

5. OAuthController.callback()
   └─→ Validates state parameter (CSRF check)
   └─→ Calls OAuthService.exchangeCodeForToken(code)
   └─→ OAuthService makes HTTPS request to Google token endpoint
   └─→ Receives access token and refresh token

6. OAuthService.getUserInfo(accessToken)
   └─→ Makes HTTPS request to Google userinfo endpoint
   └─→ Receives user's id, email, name, picture

7. AuthService.authenticateWithOAuth()
   └─→ Calls createOrUpdateUserFromOAuth()
   └─→ Finds or creates user in database
   └─→ Creates new session: AuthService.createSession(userId, "google")

8. OAuthController returns response
   └─→ Sets auth_token cookie (HttpOnly, 24-hour expiry)
   └─→ Returns session details and token to frontend
   └─→ Frontend stores token in localStorage

9. Frontend ready for API calls
   └─→ Includes "Authorization: Bearer <token>" in subsequent requests
```

### Protected Route Access Flow

```
1. Frontend makes request to protected resource
   └─→ GET /api/profile
   └─→ Header: Authorization: Bearer <token>

2. Router matches route and executes middleware chain
   └─→ AuthMiddleware.protect() executes

3. AuthMiddleware extracts and validates token
   └─→ Calls AuthService.validateToken(token)
   └─→ Checks if token exists in sessions map
   └─→ Verifies token hasn't expired

4. AuthService.validateToken()
   └─→ Returns AuthSession object containing:
       ├─ userId (user ID in database)
       ├─ provider (OAuth provider name)
       ├─ token (bearer token)
       └─ expiresAt (token expiry time)

5. Token is stored in request.authContext
   └─→ Contains: authenticated (true/false)
   └─→ Contains: userId
   └─→ Contains: session
   └─→ Contains: token

6. Handler executes
   └─→ Can access auth via AuthMiddleware.getAuthContext(req)
   └─→ Can check user via AuthUtils.getUserId(req)
   └─→ Can verify provider via AuthUtils.getProvider(req)

7. Response returned to frontend
   └─→ Includes user data or protected resources
```

### Session Refresh Flow

```
1. Frontend detects token expiring soon
   └─→ Makes POST /oauth/refresh request

2. AuthMiddleware validates current token
   └─→ Ensures user is authenticated

3. AuthService.refreshSession()
   └─→ Revokes old session
   └─→ Creates new session for same userId & provider
   └─→ Generates new token

4. Response returned with new token
   └─→ New auth_token cookie set
   └─→ Frontend updates stored token

5. Session continues seamlessly
```

## Data Flow Diagram

```
Request comes in
       ↓
┌─────────────────────────────────────┐
│ Router matches route                │
│ Extracts params, query, body        │
└─────────────────────────────────────┘
       ↓
┌─────────────────────────────────────┐
│ Middleware chain executes           │
│ (if registered)                     │
│                                     │
│ AuthMiddleware.protect():          │
│ ├─ Extract token from headers/cookie
│ ├─ Call AuthService.validateToken()
│ ├─ Check token validity & expiry
│ └─ Store in request.authContext
└─────────────────────────────────────┘
       ↓
┌─────────────────────────────────────┐
│ Route handler executes              │
│                                     │
│ Can access:                         │
│ ├─ AuthMiddleware.getAuthContext()
│ ├─ AuthUtils.getUserId()           │
│ ├─ AuthUtils.getProvider()         │
│ └─ Database user records           │
└─────────────────────────────────────┘
       ↓
┌─────────────────────────────────────┐
│ Response sent to client             │
│ ├─ Status code                      │
│ ├─ Headers (including Set-Cookie)  │
│ └─ JSON body                        │
└─────────────────────────────────────┘
```

## Service Dependencies

```
OAuthController
    ├─→ IAuthService (from DI)
    └─→ Creates: AuthSession

AuthMiddleware
    ├─→ IAuthService (from DI)
    └─→ Uses: AuthSession, AuthToken

AuthService (implements IAuthService)
    ├─→ Manages: IOAuthService instances
    ├─→ Uses: IUserService
    └─→ Stores: sessions (Map), tokens (Map)

OAuthService (implements IOAuthService)
    ├─→ Uses: haxe.Http
    ├─→ Parses: JSON responses
    └─→ Communicates: OAuth provider endpoints

DI Container
    ├─→ Registers: IAuthService → AuthService
    ├─→ Registers: IOAuthService → OAuthService (per provider)
    ├─→ Registers: IUserService → UserService
    └─→ Registers: ICacheService → CacheService
```

## State Management

```
In-Memory (Current Implementation)
├─ AuthService.sessions: Map<String, AuthSession>
└─ AuthService.tokens: Map<String, AuthToken>

Recommended for Production
├─ Database table: auth_sessions
│  ├─ session_id (primary key)
│  ├─ user_id (foreign key)
│  ├─ token
│  ├─ provider
│  ├─ created_at
│  └─ expires_at
│
├─ Database table: oauth_tokens
│  ├─ id (primary key)
│  ├─ user_id (foreign key)
│  ├─ provider
│  ├─ access_token
│  ├─ refresh_token
│  ├─ token_type
│  └─ expires_at
│
└─ Database table: oauth_accounts
   ├─ id (primary key)
   ├─ user_id (foreign key)
   ├─ provider
   ├─ provider_user_id
   └─ linked_at
```

## Security Layers

```
Request → HTTPS (Transport)
   ↓
Browser Authentication
   ├─ Secure cookie flag (production only)
   └─ HttpOnly cookie flag (enabled)
   ↓
Token Validation
   ├─ Bearer token in Authorization header
   ├─ Token must exist in sessions map
   ├─ Token must not be expired
   └─ Token signature verified
   ↓
Session Validation
   ├─ Session ID verified
   ├─ User ID verified
   ├─ Provider verified
   └─ Expiry timestamp checked
   ↓
Authorization Check
   ├─ Provider restrictions (if configured)
   ├─ Own resource protection
   └─ Role-based access control (future)
   ↓
Handler Execution
   └─ Protected resource accessed
```

This architecture provides:
- ✅ Modular, testable components
- ✅ Clear separation of concerns
- ✅ Dependency injection for flexibility
- ✅ Multiple authentication layers
- ✅ Easy provider addition
- ✅ Production-ready security
