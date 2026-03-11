# Desktop OAuth Implementation Guide

Complete guide for implementing OAuth 2.0 authentication in desktop applications using SideWinder.

## Overview

Desktop applications face unique OAuth challenges:
- **No web server** for redirect URIs
- **Can't safely store client secrets** (app binaries can be decompiled)
- **Need local callback handling**
- **Token storage security**

## Solutions Provided

### 1. Loopback Flow (Recommended for Desktop Apps with Browser)
Uses a temporary local HTTP server to receive the OAuth callback.

### 2. Device Flow (For Headless/Constrained Devices)
User authenticates on a separate device by entering a code.

### 3. Secure Token Storage
Platform-specific encrypted storage for tokens.

---

## Implementation: Loopback Flow

### Setup

**File:** `DesktopOAuthClient.hx`

```haxe
import sidewinder.DesktopOAuthClient;
import sidewinder.SecureTokenStorage;

class MyDesktopApp {
    public static function main() {
        var storage = new SecureTokenStorage("MyApp");
        
        // Check for existing valid token
        if (storage.hasValidToken()) {
            var token = storage.loadToken();
            trace("Already authenticated!");
            trace("Access token: " + token.accessToken);
            
            // Check if needs refresh
            if (storage.needsRefresh()) {
                trace("Token expiring soon, refreshing...");
                refreshToken(storage, token);
            }
            
            return;
        }
        
        // Start OAuth flow
        authenticateUser(storage);
    }
    
    static function authenticateUser(storage:SecureTokenStorage) {
        // Configure OAuth client
        var config:DesktopOAuthConfig = {
            clientId: "your_client_id_here",
            authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenEndpoint: "https://oauth2.googleapis.com/token",
            scope: "openid profile email",
            redirectUri: "http://localhost:8080/callback",
            callbackPort: 8080,
            timeoutSeconds: 300
        };
        
        var client = new DesktopOAuthClient(config);
        
        try {
            trace("Starting OAuth authentication...");
            
            // This will:
            // 1. Start local server
            // 2. Open browser
            // 3. Wait for callback
            // 4. Exchange code for token
            var tokenResponse = client.authenticate();
            
            trace("Authentication successful!");
            trace("Access token: " + tokenResponse.accessToken);
            
            // Save token securely
            var storedToken:StoredToken = {
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                expiresIn: tokenResponse.expiresIn,
                tokenType: tokenResponse.tokenType,
                scope: tokenResponse.scope,
                savedAt: Date.now(),
                provider: "google"
            };
            
            storage.saveToken(storedToken);
            trace("Token saved securely!");
            
        } catch (e:Dynamic) {
            trace("Authentication failed: " + e);
        } finally {
            client.cleanup();
        }
    }
    
    static function refreshToken(storage:SecureTokenStorage, oldToken:StoredToken) {
        if (oldToken.refreshToken == null) {
            trace("No refresh token available, need to re-authenticate");
            authenticateUser(storage);
            return;
        }
        
        var config:DesktopOAuthConfig = {
            clientId: "your_client_id_here",
            authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenEndpoint: "https://oauth2.googleapis.com/token",
            scope: "openid profile email",
            redirectUri: "http://localhost:8080/callback"
        };
        
        var client = new DesktopOAuthClient(config);
        
        try {
            var newToken = client.refreshToken(oldToken.refreshToken);
            
            var storedToken:StoredToken = {
                accessToken: newToken.accessToken,
                refreshToken: newToken.refreshToken,
                expiresIn: newToken.expiresIn,
                tokenType: newToken.tokenType,
                scope: newToken.scope,
                savedAt: Date.now(),
                provider: oldToken.provider
            };
            
            storage.saveToken(storedToken);
            trace("Token refreshed successfully!");
            
        } catch (e:Dynamic) {
            trace("Token refresh failed: " + e);
            trace("Re-authenticating...");
            authenticateUser(storage);
        }
    }
}
```

### Key Features

- **Automatic browser launch** (Windows/Mac/Linux)
- **PKCE by default** (no client secret needed)
- **Local callback server** (runs on localhost)
- **Beautiful success page** shown to user
- **Timeout handling** (default 5 minutes)

---

## Implementation: Device Flow

### Setup

**File:** `DeviceFlowOAuthClient.hx`

Perfect for:
- CLI tools
- Headless servers
- Devices without browsers
- Constrained devices (IoT, embedded)

```haxe
import sidewinder.DeviceFlowOAuthClient;
import sidewinder.SecureTokenStorage;

class MyDeviceApp {
    public static function main() {
        var storage = new SecureTokenStorage("MyDeviceApp");
        
        // Check for existing token
        if (storage.hasValidToken()) {
            var token = storage.loadToken();
            trace("Already authenticated!");
            return;
        }
        
        authenticateDevice(storage);
    }
    
    static function authenticateDevice(storage:SecureTokenStorage) {
        var config:DeviceFlowConfig = {
            clientId: "your_client_id",
            deviceAuthorizationEndpoint: "https://oauth2.googleapis.com/device/code",
            tokenEndpoint: "https://oauth2.googleapis.com/token",
            scope: "openid profile email"
        };
        
        var client = new DeviceFlowOAuthClient(config);
        
        try {
            trace("Starting device flow authentication...");
            
            // Request device code
            var deviceCode = client.requestDeviceCode();
            
            // Display instructions (automatically formatted)
            trace("\n============================================================");
            trace("DEVICE AUTHORIZATION");
            trace("============================================================");
            trace("");
            trace("1. Visit: " + deviceCode.verificationUri);
            trace("2. Enter code: " + deviceCode.userCode);
            trace("");
            trace("Waiting for authorization...");
            trace("Code expires in " + deviceCode.expiresIn + " seconds");
            trace("============================================================\n");
            
            // Poll for authorization (blocking)
            var tokenResponse = client.pollForAuthorization(deviceCode);
            
            trace("Authentication successful!");
            
            // Save token
            var storedToken:StoredToken = {
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                expiresIn: tokenResponse.expiresIn,
                tokenType: tokenResponse.tokenType,
                scope: tokenResponse.scope,
                savedAt: Date.now(),
                provider: "google"
            };
            
            storage.saveToken(storedToken);
            trace("Token saved!");
            
        } catch (e:Dynamic) {
            trace("Authentication failed: " + e);
        }
    }
}
```

### Device Flow Features

- **No browser required** on the device
- **User-friendly codes** (e.g., "WDJB-MJHT")
- **Automatic polling** with proper intervals
- **Timeout handling**
- **QR code support** (via verificationUriComplete)

---

## Secure Token Storage

### Platform-Specific Security

**File:** `SecureTokenStorage.hx`

- **Windows**: Credential Manager (fallback to encrypted file)
- **macOS**: Keychain (fallback to encrypted file)
- **Linux**: libsecret/secret-tool (fallback to encrypted file)

### Usage

```haxe
var storage = new SecureTokenStorage("MyApp");

// Save token
var token:StoredToken = {
    accessToken: "abc123",
    refreshToken: "xyz789",
    expiresIn: 3600,
    tokenType: "Bearer",
    scope: "openid profile email",
    savedAt: Date.now(),
    provider: "google"
};

storage.saveToken(token);

// Load token
var loadedToken = storage.loadToken();
if (loadedToken != null) {
    trace("Access token: " + loadedToken.accessToken);
}

// Check validity
if (storage.hasValidToken()) {
    trace("Token is still valid!");
}

// Check if needs refresh
if (storage.needsRefresh()) {
    trace("Token expiring soon, should refresh");
}

// Delete token (logout)
storage.deleteToken();
```

---

## OAuth Provider Configurations

### Google OAuth

```haxe
var config:DesktopOAuthConfig = {
    clientId: "YOUR_CLIENT_ID.apps.googleusercontent.com",
    authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenEndpoint: "https://oauth2.googleapis.com/token",
    scope: "openid profile email",
    redirectUri: "http://localhost:8080/callback",
    callbackPort: 8080
};
```

**Setup OAuth App:**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create OAuth 2.0 Client ID
3. Type: "Desktop app"
4. Add redirect URI: `http://localhost:8080/callback`

### GitHub OAuth

```haxe
var config:DesktopOAuthConfig = {
    clientId: "your_github_client_id",
    authorizationEndpoint: "https://github.com/login/oauth/authorize",
    tokenEndpoint: "https://github.com/login/oauth/access_token",
    scope: "user:email",
    redirectUri: "http://localhost:8080/callback",
    callbackPort: 8080
};
```

**Setup OAuth App:**
1. Go to GitHub Settings > Developer settings > OAuth Apps
2. Create new OAuth App
3. Authorization callback URL: `http://localhost:8080/callback`

### Microsoft OAuth

```haxe
var config:DesktopOAuthConfig = {
    clientId: "your_microsoft_client_id",
    authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
    tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
    scope: "openid profile email",
    redirectUri: "http://localhost:8080/callback",
    callbackPort: 8080
};
```

**Setup OAuth App:**
1. Go to [Azure Portal](https://portal.azure.com)
2. Register application
3. Platform: Mobile and desktop applications
4. Add redirect URI: `http://localhost:8080/callback`

---

## Best Practices

### 1. **Always Use PKCE**
✅ Enabled by default in `DesktopOAuthClient`
- No client secret needed
- Protection against authorization code interception

### 2. **Store Tokens Securely**
✅ Use `SecureTokenStorage`
- Platform-specific secure storage
- Never store tokens in plain text
- Never commit tokens to source control

### 3. **Handle Token Expiry**
```haxe
if (storage.hasValidToken()) {
    if (storage.needsRefresh()) {
        // Refresh before it expires
        refreshToken();
    }
} else {
    // Re-authenticate
    authenticate();
}
```

### 4. **Timeout Handling**
```haxe
var config:DesktopOAuthConfig = {
    // ... other config
    timeoutSeconds: 300 // 5 minutes
};
```

### 5. **Error Handling**
```haxe
try {
    var token = client.authenticate();
} catch (e:Dynamic) {
    if (e == "Timeout waiting for OAuth callback") {
        trace("User didn't complete authentication in time");
    } else if (e == "State mismatch - possible CSRF attack") {
        trace("Security issue detected");
    } else {
        trace("Unknown error: " + e);
    }
}
```

### 6. **Cleanup Resources**
```haxe
try {
    var token = client.authenticate();
} finally {
    client.cleanup(); // Always cleanup the loopback server
}
```

---

## Architecture Diagram

```
Desktop App Flow:

┌──────────────┐
│ Desktop App  │
└──────┬───────┘
       │ 1. Start OAuth
       ▼
┌──────────────────────┐
│ DesktopOAuthClient   │
│ - Start local server │
│ - Generate PKCE      │
│ - Open browser       │
└──────┬───────────────┘
       │ 2. Browser opens
       ▼
┌────────────────────┐
│ OAuth Provider     │
│ (Google/GitHub)    │
└────────┬───────────┘
         │ 3. User authenticates
         ▼
┌──────────────────────┐
│ Redirect to:         │
│ localhost:8080       │
└────────┬─────────────┘
         │ 4. Callback
         ▼
┌──────────────────────┐
│ Loopback Server      │
│ - Capture code       │
│ - Display success    │
└────────┬─────────────┘
         │ 5. Exchange code
         ▼
┌────────────────────┐
│ Get Access Token   │
└────────┬───────────┘
         │ 6. Save securely
         ▼
┌────────────────────────┐
│ SecureTokenStorage     │
│ - Keychain (Mac)       │
│ - Credential Mgr (Win) │
│ - Keyring (Linux)      │
└────────────────────────┘
```

---

## Device Flow Architecture

```
Device Flow:

┌──────────────┐
│ Device App   │
└──────┬───────┘
       │ 1. Request device code
       ▼
┌──────────────────────┐
│ OAuth Provider       │
└──────┬───────────────┘
       │ 2. Return: user_code + verification_uri
       ▼
┌──────────────────────┐
│ Display to User:     │
│ "Visit URL"          │
│ "Enter Code: ABCD"   │
└──────────────────────┘

User opens URL on phone/computer ──┐
                                    │
                                    ▼
                          ┌────────────────────┐
                          │ OAuth Provider     │
                          │ User authenticates │
                          └────────────────────┘
                                    │
┌──────────────┐                   │
│ Device App   │◄──────────────────┘
│ Polls every  │     Authorization granted
│ 5 seconds    │
└──────┬───────┘
       │ Get access token
       ▼
┌────────────────────────┐
│ SecureTokenStorage     │
└────────────────────────┘
```

---

## Troubleshooting

### "Port already in use"
```haxe
// Try a different port
var config:DesktopOAuthConfig = {
    // ...
    callbackPort: 8081 // or 8082, 8083, etc.
};
```

### "State mismatch"
- Indicates CSRF attack or browser issue
- Make sure only one OAuth flow is active at a time
- Clear browser cookies and retry

### "Authorization timeout"
- User didn't complete auth in time
- Increase timeout: `timeoutSeconds: 600` (10 minutes)

### "Failed to open browser"
- Manually copy the URL and open in browser
- On headless systems, use Device Flow instead

### Token not persisting
- Check storage directory permissions
- Verify Keychain/Credential Manager access
- Fall back to encrypted file if OS security not available

---

## Security Considerations

✅ **Use PKCE** (Proof Key for Code Exchange)
- Protects against authorization code interception
- Required for public clients (desktop apps)

✅ **Never embed client secrets** in desktop apps
- Can be extracted from binaries
- Use PKCE instead

✅ **Secure token storage**
- Use OS-provided secure storage
- Encrypt tokens at rest
- Never log tokens

✅ **Validate state parameter**
- Prevents CSRF attacks
- Always check state matches

✅ **Use localhost for redirects**
- Never use public URLs for desktop apps
- Prevents redirect hijacking

✅ **Handle token expiry**
- Refresh before expiry
- Implement automatic refresh logic

❌ **Don't store tokens in:**
- Plain text files
- Application preferences (unencrypted)
- Git repositories
- Log files

---

## Complete Example

See `examples/DesktopOAuthExample.hx` for a full working example with:
- Token storage
- Automatic refresh
- Error handling
- Multi-provider support

---

## Next Steps

1. **Choose your flow**:
   - Browser available? → Use Loopback Flow
   - Headless/CLI? → Use Device Flow

2. **Register your OAuth app** with provider

3. **Implement authentication** using examples above

4. **Test thoroughly** with different scenarios

5. **Consider adding**:
   - Automatic token refresh
   - Multiple provider support
   - User account linking
   - Offline access (refresh tokens)

---

## Additional Resources

- [OAuth 2.0 for Native Apps (RFC 8252)](https://tools.ietf.org/html/rfc8252)
- [OAuth 2.0 Device Flow (RFC 8628)](https://tools.ietf.org/html/rfc8628)
- [PKCE (RFC 7636)](https://tools.ietf.org/html/rfc7636)

---

## License

Part of the SideWinder HTTP framework.
