# Desktop Cookie Persistence - Quick Reference

## 5-Minute Setup

### 1. Add to your app initialization:
```haxe
import sidewinder.PersistentCookieJar;
import sidewinder.AutoClientAsync;

function init() {
    var cookieJar = new PersistentCookieJar();
    AutoClientAsync.globalCookieJar = cookieJar;
}
```

### 2. Use any auto-generated client:
```haxe
var client = MyService.create(IMyService, "https://api.example.com");
// Cookies are automatically persisted!
```

### 3. Verify persistent storage:
```haxe
// On first run: ~/.sidewinder/cookies.json is created
// On app restart: Cookies from previous session are loaded automatically
```

## Common Tasks

### Save a backup
```haxe
var jar = new PersistentCookieJar();
var backup = jar.exportCookies();
sys.io.File.saveContent("backup.json", backup);
```

### Restore from backup
```haxe
var jar = new PersistentCookieJar();
var backup = sys.io.File.getContent("backup.json");
jar.importCookies(backup);
```

### Use custom storage path
```haxe
var jar = new PersistentCookieJar("/app/data");
```

### Clear all cookies
```haxe
jar.clear(); // Clears memory and saves to disk
jar.clearAndDeleteFile(); // Also deletes the file
```

### Check authentication
```haxe
var cookies = jar.getAllCookies();
var isAuth = cookies.length > 0;
```

## File Locations

| OS | Default Path |
|----|--------------|
| Linux/macOS | `~/.sidewinder/cookies.json` |
| Windows | `%USERPROFILE%\.sidewinder\cookies.json` |
| Custom | Pass to constructor |

## Cookie File Format

```json
{
  "cookies": [
    {
      "name": "session_id",
      "value": "token123",
      "domain": "api.example.com",
      "path": "/",
      "secure": true,
      "httpOnly": true,
      "sameSite": "Lax"
    }
  ],
  "savedAt": "timestamp"
}
```

## API Summary

### Constructor
- `new PersistentCookieJar(?storagePath:String)`

### Core Methods
- `setCookie(header:String, url:String):Void` - Override: auto-saves
- `getCookieHeader(url:String):String` - Get cookies for URL
- `getAllCookies():Array<Cookie>` - Get all stored

### Utility Methods
- `clear():Void` - Clear all (saves)
- `clearAndDeleteFile():Void` - Delete file too
- `exportCookies():String` - JSON backup
- `importCookies(json:String):Void` - Restore from JSON
- `getStoragePath():String` - Get storage directory

## Features

✓ Automatic save on every change  
✓ Auto-load on startup  
✓ Expired cookie cleanup  
✓ Cross-platform paths  
✓ Import/export support  
✓ Full logging  
✓ Backwards compatible  
✓ Thread-safe (via parent)  

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Cookies not saved | Check disk permissions on `~/.sidewinder/` |
| Stale cookies | Clear with `clearAndDeleteFile()` |
| Custom path not working | Ensure directory is writable |
| File permission denied | Run with proper permissions |
| Large number of cookies | May slow down saves (consider limiting) |

## Example: OAuth with Persistence

```haxe
class OAuthApp {
    private var cookies:PersistentCookieJar;
    private var client:MyAuthClient;
    
    public function new() {
        cookies = new PersistentCookieJar();
        AutoClientAsync.globalCookieJar = cookies;
        
        if (cookies.getAllCookies().length > 0) {
            // Previously authenticated
            verifySession();
        } else {
            // Need new login
            performLogin();
        }
    }
    
    function performLogin() {
        client.authenticateAsync(onLoginSuccess, onLoginError);
    }
    
    function onLoginSuccess(token:String) {
        // Cookies are auto-persisted here
        trace("Logged in! Cookies saved to disk");
    }
}
```

## See Also

- `DESKTOP_COOKIE_PERSISTENCE.md` - Complete guide
- `DesktopAppExample.hx` - Full example code
- `DesktopOAuthClient.hx` - OAuth with cookies
- `CookieJar.hx` - Base implementation

## Testing Persistence

```bash
# Test 1: Run app, note cookies saved
ls ~/.sidewinder/
cat ~/.sidewinder/cookies.json

# Test 2: Restart app, verify cookies loaded
# (check logs or debug output)

# Test 3: Export and import
# See Examples section above
```

## Performance Notes

- Cookies saved to JSON on every change
- Expired cookies auto-cleaned on load/save
- No background threads - synchronous saves
- For 1000+ cookies: consider selective persistence
- JSON format is human-readable but not compressed

## Security Notes

- Files stored with default OS permissions
- Use `chmod 700` on Unix for extra security
- Don't store plaintext secrets in cookies
- Use short-lived tokens + refresh tokens
- Respect cookie security flags (Secure, HttpOnly, SameSite)

---

**Questions?** See `DESKTOP_COOKIE_PERSISTENCE.md` for detailed documentation.
