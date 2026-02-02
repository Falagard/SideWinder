# OAuth Authentication API Specification

## OAuth Flow Endpoints

### 1. Authorization Endpoint
**GET** `/oauth/authorize/:provider`

Redirects the user to the OAuth provider's login page.

**Path Parameters:**
- `provider` (string): OAuth provider name (e.g., "google", "github", "microsoft")

**Query Parameters:**
- `redirect_uri` (string, optional): URL to redirect to after OAuth flow
- `use_pkce` (boolean, optional): Enable PKCE security (default: false)
- `state` (string, optional): CSRF protection state (auto-generated if not provided)

**Response:**
- HTTP 302 Redirect to OAuth provider authorization URL

**Example:**
```
GET /oauth/authorize/google
HTTP/1.1 302 Found
Location: https://accounts.google.com/o/oauth2/v2/auth?client_id=...&scope=...&state=...
```

---

### 2. Callback Endpoint
**GET** `/oauth/callback/:provider`

OAuth provider redirects back to this endpoint with authorization code.

**Path Parameters:**
- `provider` (string): OAuth provider name

**Query Parameters:**
- `code` (string): Authorization code from provider
- `state` (string): State parameter for CSRF verification
- `error` (string, optional): Error code if auth failed

**Response:**
```json
{
  "success": true,
  "session": {
    "sessionId": "ABC123...",
    "userId": 42,
    "provider": "google",
    "expiresAt": "2026-02-02T00:00:00Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Cookies Set:**
- `auth_token`: JWT token (HttpOnly, 24-hour expiry)

**Status Codes:**
- 200: Success
- 400: Invalid code or state
- 500: Server error

---

### 3. Current User Endpoint
**GET** `/oauth/user`

Get current authenticated user information.

**Authentication:** Required
- Bearer token in Authorization header, OR
- auth_token cookie

**Response:**
```json
{
  "userId": 42,
  "provider": "google",
  "expiresAt": "2026-02-02T00:00:00Z"
}
```

**Status Codes:**
- 200: Success
- 401: Not authenticated
- 500: Server error

---

### 4. Logout Endpoint
**GET** `/oauth/logout`

Logout current user and revoke session.

**Authentication:** Required

**Response:**
```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

**Cookies Modified:**
- `auth_token`: Cleared (Max-Age: 0)

**Status Codes:**
- 200: Success
- 401: Not authenticated

---

### 5. Refresh Session Endpoint
**POST** `/oauth/refresh`

Refresh current authentication session.

**Authentication:** Required

**Request Body:** (empty)

**Response:**
```json
{
  "success": true,
  "session": {
    "sessionId": "XYZ789...",
    "userId": 42,
    "provider": "google",
    "expiresAt": "2026-02-03T00:00:00Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Status Codes:**
- 200: Success
- 401: Not authenticated
- 500: Server error

---

## Protected Resource Example

### Get User Profile
**GET** `/api/profile`

Get authenticated user's profile.

**Headers:**
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

Or request will automatically use `auth_token` cookie if present.

**Response:**
```json
{
  "id": 42,
  "name": "John Doe",
  "email": "john@example.com",
  "provider": "google"
}
```

**Status Codes:**
- 200: Success
- 401: Not authenticated (missing or invalid token)
- 404: User not found

---

## Error Responses

### 401 Unauthorized
```json
{
  "error": "Unauthorized",
  "message": "Authentication required"
}
```

### 403 Forbidden
```json
{
  "error": "Forbidden",
  "message": "This provider is not allowed for this route"
}
```

### 400 Bad Request
```json
{
  "error": "OAuth error: invalid_request",
  "message": "Authorization code is missing"
}
```

### 500 Internal Server Error
```json
{
  "error": "OAuth error: Failed to exchange code for token"
}
```

---

## Authentication Methods

### Method 1: Bearer Token (Recommended for APIs)
```
Authorization: Bearer <token>
```

### Method 2: Cookie (Automatic)
```
Cookie: auth_token=<token>
```

### Method 3: Query Parameter
```
GET /api/resource?token=<token>
```

---

## OAuth Providers

### Google
- **Client ID**: Required
- **Client Secret**: Required
- **Scope**: `openid profile email`
- **Endpoints:**
  - Authorization: `https://accounts.google.com/o/oauth2/v2/auth`
  - Token: `https://oauth2.googleapis.com/token`
  - User Info: `https://openidconnect.googleapis.com/v1/userinfo`

### GitHub
- **Client ID**: Required
- **Client Secret**: Required
- **Scope**: `user:email`
- **Endpoints:**
  - Authorization: `https://github.com/login/oauth/authorize`
  - Token: `https://github.com/login/oauth/access_token`
  - User Info: `https://api.github.com/user`

### Microsoft
- **Client ID**: Required
- **Client Secret**: Required
- **Scope**: `openid profile email`
- **Endpoints:**
  - Authorization: `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`
  - Token: `https://login.microsoftonline.com/common/oauth2/v2.0/token`
  - User Info: `https://graph.microsoft.com/v1.0/me`

---

## Session Details

### Session Lifetime
- **Default Expiry**: 24 hours
- **Refresh**: Can be extended via `/oauth/refresh`
- **Auto-expiry**: Tokens expire automatically after 24 hours

### Session Structure
```haxe
typedef AuthSession = {
  var sessionId:String;      // Unique session identifier
  var userId:Int;            // Local user ID
  var token:AuthToken;       // Auth token details
  var provider:String;       // OAuth provider name
  var expiresAt:Date;       // Session expiry time
}

typedef AuthToken = {
  var token:String;         // JWT/Bearer token
  var userId:Int;           // User ID
  var expiresAt:Date;       // Token expiry
  var createdAt:Date;       // Creation timestamp
}
```

---

## PKCE Support

PKCE (Proof Key for Code Exchange) is supported for public clients.

**Enable PKCE:**
```
GET /oauth/authorize/google?use_pkce=true
```

**PKCE Flow:**
1. Client generates code verifier (128 random characters)
2. Client generates code challenge (SHA256 hash)
3. Authorization request includes code_challenge
4. Token exchange request includes code_verifier
5. Server validates code_verifier matches code_challenge

---

## Rate Limiting (Not Implemented - Recommended)

For production, implement rate limiting:
- OAuth endpoints: 10 requests per minute per IP
- Token refresh: 20 requests per minute per user
- Login endpoints: 5 attempts per 15 minutes per email

---

## Security Headers (Recommended)

Set these headers in production:

```
Content-Security-Policy: default-src 'self'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

---

## Postman Examples

### Login with Google
```
GET {{baseUrl}}/oauth/authorize/google
```

### Get Current User
```
GET {{baseUrl}}/oauth/user
Authorization: Bearer {{token}}
```

### Logout
```
GET {{baseUrl}}/oauth/logout
Authorization: Bearer {{token}}
```

### Refresh Session
```
POST {{baseUrl}}/oauth/refresh
Authorization: Bearer {{token}}
```

### Access Protected Resource
```
GET {{baseUrl}}/api/profile
Authorization: Bearer {{token}}
```

---

## Implementation Checklist

- [ ] Environment variables configured
- [ ] DI container initialized with auth services
- [ ] Routes registered with ExampleAuthApp or custom implementation
- [ ] OAuth providers configured (Google, GitHub, Microsoft)
- [ ] Frontend OAuth buttons point to `/oauth/authorize/:provider`
- [ ] Frontend stores token from `/oauth/callback/:provider` response
- [ ] Frontend includes token in `Authorization` header for API calls
- [ ] User database has field for OAuth provider ID
- [ ] HTTPS enabled in production
- [ ] Secure flag enabled for cookies in production
- [ ] CORS configured if needed
- [ ] Rate limiting implemented
- [ ] Error handling in frontend for 401 responses
- [ ] Token refresh logic implemented in frontend
