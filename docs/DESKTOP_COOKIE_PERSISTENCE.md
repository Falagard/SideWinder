# Desktop Cookie Persistence Guide

## Overview

The `PersistentCookieJar` class enables automatic cookie persistence for desktop applications. Cookies are automatically saved to a JSON file and restored on application startup, allowing users to maintain authentication sessions across application restarts.

## Key Features

- **Automatic Persistence**: Cookies are saved to disk automatically when modified
- **Expired Cookie Cleanup**: Expired cookies are filtered out during save/load
- **Secure Location**: Cookies stored in `~/.sidewinder/` by default (user's home directory)
- **Import/Export**: Backup and restore cookies programmatically
- **JSON Format**: Human-readable cookie storage format
- **Thread-Safe**: Built on the same system as the in-memory CookieJar

## Setup

### Basic Usage

Replace the default in-memory cookie jar with a persistent one for desktop apps:

```haxe
import sidewinder.PersistentCookieJar;
import sidewinder.AutoClientAsync;

// Early in your application initialization:
function initializeCookies():Void {
    var persistentJar = new PersistentCookieJar();
    AutoClientAsync.globalCookieJar = persistentJar;
}
```

### Custom Storage Path

Store cookies in a specific directory:

```haxe
var persistentJar = new PersistentCookieJar("/path/to/app/data");
AutoClientAsync.globalCookieJar = persistentJar;
```

### Per-Client Cookies

Create separate cookie jars for different API endpoints:

```haxe
var apiCookies = new PersistentCookieJar("/app/cookies/api");
var authCookies = new PersistentCookieJar("/app/cookies/auth");

var apiClient = MyApiClient.create(MyApiInterface, "https://api.example.com", apiCookies);
var authClient = MyAuthClient.create(MyAuthInterface, "https://auth.example.com", authCookies);
```

## Cookie File Format

Cookies are stored in `~/.sidewinder/cookies.json`:

```json
{
  "cookies": [
    {
      "name": "session_id",
      "value": "abc123def456",
      "domain": "api.example.com",
      "path": "/",
      "secure": true,
      "httpOnly": true,
      "sameSite": "Lax",
      "createdAt": 1708099200000
    }
  ],
  "savedAt": "2025-02-05 10:00:00"
}
```

## Advanced Usage

### Export Cookies for Backup

```haxe
var persistentJar = new PersistentCookieJar();

// Export all cookies as JSON
var backupJson = persistentJar.exportCookies();

// Save to file or send to server
sys.io.File.saveContent("cookies_backup.json", backupJson);
```

### Import Cookies

```haxe
var persistentJar = new PersistentCookieJar();

// Load cookies from backup
var backupData = sys.io.File.getContent("cookies_backup.json");
persistentJar.importCookies(backupData);
```

### Clear All Cookies

```haxe
var persistentJar = new PersistentCookieJar();

// Option 1: Clear from memory only (will be deleted on next save)
persistentJar.clear();

// Option 2: Clear from memory and delete the file
persistentJar.clearAndDeleteFile();
```

### Get Storage Path

```haxe
var persistentJar = new PersistentCookieJar();
var path = persistentJar.getStoragePath();
trace('Cookies stored at: $path');
```

## OAuth Integration

For desktop OAuth flows, use persistent cookies to maintain authentication:

```haxe
class DesktopApp {
    private var cookieJar:PersistentCookieJar;
    private var client:MyAuthClient;
    
    public function new() {
        // Set up persistent cookies for OAuth state
        cookieJar = new PersistentCookieJar();
        AutoClientAsync.globalCookieJar = cookieJar;
        
        // Create authenticated client
        client = MyAuthClient.create(MyAuthInterface, "https://api.example.com", cookieJar);
    }
    
    public function login():Void {
        // Perform OAuth flow - cookies are automatically persisted
        client.authenticateAsync(handleLoginSuccess, handleLoginError);
    }
    
    public function restoreSession():Void {
        // On app restart, cookies are automatically loaded from disk
        // Previous authentication is preserved
        client.getUserAsync(handleUserFetched, handleError);
    }
}
```

## Cookie Storage Directory Behavior

### Platform-Specific Locations

The default storage location is determined by:

1. **Linux/macOS**: `~/.sidewinder/`
   - Example: `/home/username/.sidewinder/cookies.json`

2. **Windows**: `%USERPROFILE%\.sidewinder\`
   - Example: `C:\Users\username\.sidewinder\cookies.json`

### Directory Creation

The storage directory is created automatically if it doesn't exist.

### Custom Location

Specify a custom location for app-specific or portable installations:

```haxe
// App-specific directory
var appDataPath = Sys.getEnv("APPDATA") ?? "./appdata";
var cookieJar = new PersistentCookieJar('$appDataPath/SideWinder');

// Or relative to application directory
var cookieJar = new PersistentCookieJar("./data");
```

## Security Considerations

### File Permissions

Cookie files are stored with default permissions. For sensitive applications:

```haxe
// After creating the jar, secure the directory on Unix
#if (neko || hl)
Sys.command('chmod 700 ~/.sidewinder');
#end
```

### Cookie Attributes

The persistent jar respects cookie security flags:

- **Secure**: Cookies marked as secure are stored but should only be sent over HTTPS
- **HttpOnly**: Stored cookies maintain the HttpOnly flag for reference
- **SameSite**: Same-site policy is preserved in storage

### Sensitive Data

Do not store plaintext passwords or API keys in cookies. Use:

- **Short-lived tokens**: Access tokens that expire quickly
- **Refresh tokens**: Stored securely with appropriate expiration
- **Session identifiers**: Hashed IDs without sensitive data

## Troubleshooting

### Cookies Not Persisting

1. Check file system permissions on the storage directory
2. Verify the directory exists and is writable
3. Check logs for permission or write errors

### Stale Cookies

The persistent jar automatically removes expired cookies when:
- Loading from disk
- Adding new cookies
- Saving to disk

To force a cleanup:

```haxe
var persistentJar = new PersistentCookieJar();
persistentJar.clear();
persistentJar.clearAndDeleteFile();
```

### Performance

For large numbers of cookies (>1000):
- Cookies are serialized to JSON on every change
- Consider limiting stored cookies or implementing selective persistence
- Monitor disk I/O if saving very frequently

## Examples

See `DesktopOAuthClient.hx` for OAuth integration with cookies, or check the test files for additional examples.

## API Reference

### Constructor

```haxe
new PersistentCookieJar(?storagePath:String)
```

- `storagePath`: Optional directory for cookie storage (defaults to `~/.sidewinder/`)

### Methods

#### From ICookieJar interface (inherited)

- `setCookie(setCookieHeader:String, url:String):Void` - Parse and store cookies
- `getCookieHeader(url:String):String` - Get cookies for a URL
- `getAllCookies():Array<Cookie>` - Get all stored cookies
- `clear():Void` - Clear all cookies and save

#### Additional methods

- `clearAndDeleteFile():Void` - Clear cookies and delete the file
- `exportCookies():String` - Export cookies as JSON
- `importCookies(jsonData:String):Void` - Import cookies from JSON
- `getStoragePath():String` - Get the directory where cookies are stored
