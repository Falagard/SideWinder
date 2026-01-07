# HTML5 Polling Client Guide

## Overview

The `PollingClient` now supports **both sys targets (HashLink, C++, etc.) and HTML5/JavaScript** targets through conditional compilation. The same API works across all platforms!

## Platform Differences

| Feature | Sys Targets | HTML5/JS |
|---------|-------------|----------|
| Threading | ✅ Background thread | ❌ Uses timers instead |
| Mutex | ✅ Thread-safe | ❌ Not needed (single-threaded) |
| Blocking | ✅ Can use `Sys.sleep()` | ❌ Uses `Timer.delay()` |
| HTTP | ✅ `haxe.Http` | ✅ `haxe.Http` (uses XHR) |

## Usage (Same API for All Platforms!)

```haxe
import sidewinder.PollingClient;
import sidewinder.IMessageClient;

// Create client (works on sys AND HTML5!)
var client:IMessageClient = new PollingClient("http://127.0.0.1:8000");

// Set up event handlers
client.onConnect = () -> trace("Connected!");
client.onMessage = (msg) -> trace("Message: " + msg);
client.onError = (err) -> trace("Error: " + err);
client.onDisconnect = () -> trace("Disconnected");

// Connect
client.connect();

// Later: disconnect
client.disconnect();
```

## Building for HTML5

### Option 1: Compile Haxe to JavaScript

Create a simple HTML5 client:

```bash
# Create a build file: build.hxml
-cp Source
-main PollingClientDemo
-js static/polling_client.js
-lib lime
```

Then compile:

```bash
haxe build.hxml
```

### Option 2: Use the Pure JavaScript Demo

We've included a ready-to-use HTML demo at [`static/polling_demo.html`](file:///c:/Src/ge/SideWinder/static/polling_demo.html) that works without compilation.

## Testing HTML5 Client

### 1. Start the Server

```bash
lime test hl
```

Server will run on `http://127.0.0.1:8000`

### 2. Open the Demo Page

Simply open `static/polling_demo.html` in your browser, or serve it via the SideWinder server:

```
http://127.0.0.1:8000/polling_demo.html
```

### 3. Click "Connect"

The page will:
- ✅ Subscribe to the server
- ✅ Start polling for messages
- ✅ Display messages in real-time
- ✅ Show connection status

## Implementation Details

### Sys Targets (HashLink, C++, etc.)

```haxe
#if sys
// Uses Thread for background polling
pollingThread = Thread.create(() -> {
    pollingLoop();
});

// Uses Mutex for thread safety
mutex.acquire();
// ... critical section ...
mutex.release();

// Can block with Sys.sleep()
Sys.sleep(1.0);
#end
```

### HTML5/JavaScript Targets

```haxe
#if (js || html5)
// Uses Timer for periodic polling
pollingTimer = new Timer(100); // 100ms interval
pollingTimer.run = () -> {
    if (shouldRun && connected && !isPolling) {
        pollOnce();
    }
};

// No mutex needed (single-threaded)
// Uses Timer.delay() instead of Sys.sleep()
Timer.delay(() -> {
    // Reconnect logic
}, Std.int(delay * 1000));
#end
```

## CORS Considerations

When running the HTML5 client from a different origin than the server, you may need to enable CORS. In `Main.hx`:

```haxe
SideWinderRequestHandler.corsEnabled = true; // Enable CORS
```

This is already set to `false` by default. Change it to `true` if you're serving the HTML from a different domain/port.

## Example: Embedding in Your HTML5 App

```html
<!DOCTYPE html>
<html>
<head>
    <title>My App</title>
    <script src="polling_client.js"></script>
</head>
<body>
    <div id="messages"></div>
    
    <script>
        // Assuming your Haxe code exports a PollingClient class
        var client = new PollingClient("http://127.0.0.1:8000");
        
        client.onMessage = function(msg) {
            var data = JSON.parse(msg);
            document.getElementById('messages').innerHTML += 
                '<div>' + data.message + '</div>';
        };
        
        client.connect();
    </script>
</body>
</html>
```

## Performance Notes

### Sys Targets
- **Polling**: Blocks for up to 30 seconds (long-polling)
- **Overhead**: One thread per client
- **Efficiency**: Very efficient, server holds connection

### HTML5 Targets
- **Polling**: Checks every 100ms (configurable)
- **Overhead**: Timer-based, non-blocking
- **Efficiency**: More frequent requests, but necessary for browser environment

## Troubleshooting

### "Client not subscribed" Error

Make sure the server is running and the `/poll/subscribe` endpoint is accessible:

```bash
curl -X POST http://localhost:8000/poll/subscribe \
  -H "Content-Type: application/json" \
  -d '{"clientId": "test123"}'
```

### CORS Errors in Browser

Enable CORS in `Main.hx`:

```haxe
SideWinderRequestHandler.corsEnabled = true;
```

### No Messages Received

1. Check browser console for errors
2. Verify server is broadcasting messages
3. Test with the demo page first

## Migration Path

The beauty of this design is that **the same code works everywhere**:

```haxe
// This works on sys, HTML5, and future WebSocket implementations!
var client:IMessageClient = new PollingClient(serverUrl);
client.onMessage = handleMessage;
client.connect();
```

When WebSockets are added:

```haxe
// Just change the implementation class
#if sys
var client:IMessageClient = new WebSocketClient(serverUrl);
#else
var client:IMessageClient = new PollingClient(serverUrl);
#end
```

Or use a factory pattern:

```haxe
class MessageClientFactory {
    public static function create(url:String):IMessageClient {
        #if websocket_available
        return new WebSocketClient(url);
        #else
        return new PollingClient(url);
        #end
    }
}
```

## Summary

✅ **Cross-platform** - Same API for sys and HTML5  
✅ **No code changes** - Conditional compilation handles differences  
✅ **Production-ready** - Works in browsers and native apps  
✅ **Future-proof** - Easy to swap for WebSockets later  

The polling client is now truly universal! 🎉
