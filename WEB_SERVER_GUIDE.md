# Web Server Abstraction Guide

## Overview

SideWinder now supports multiple HTTP server implementations through a unified interface (`IWebServer`). This allows you to easily switch between different web server backends without changing your application code.

## Supported Implementations

### 1. **SnakeServer** (Default)
- **Target:** HashLink (hl)
- **Description:** The original snake-server implementation
- **Characteristics:**
  - Threaded request handling
  - Built on Haxe's sys.net.Socket
  - Well-tested with SideWinder
  - Full feature support

### 2. **CivetWeb** (Production Ready)
- **Target:** HashLink (hl)
- **Description:** Lightweight, embeddable C web server
- **Characteristics:**
  - Native C implementation via .hdll
  - Very lightweight and fast
  - Cross-platform (Windows, Linux, macOS)
  - Native bindings included in project

## Architecture

### Core Interface: `IWebServer`

```haxe
interface IWebServer {
    public function start():Void;
    public function handleRequest():Void;
    public function stop():Void;
    public function getHost():String;
    public function getPort():Int;
    public function isRunning():Bool;
}
```

### Factory Pattern

The `WebServerFactory` provides a centralized way to create server instances:

```haxe
// Explicit server type selection
var server = WebServerFactory.create(
    WebServerType.SnakeServer,  // or WebServerType.CivetWeb
    "127.0.0.1",
    8000,
    SideWinderRequestHandler  // Required for SnakeServer
);
server.start();
```

## Usage Examples

### Basic Server Setup

```haxe
import sidewinder.IWebServer;
import sidewinder.WebServerFactory;
import sidewinder.WebServerFactory.WebServerType;

class MyApp {
    private var webServer:IWebServer;
    
    public function new() {
        // Create server instance
        webServer = WebServerFactory.create(
            WebServerType.SnakeServer,
            "127.0.0.1",
            8000,
            SideWinderRequestHandler
        );
        
        // Start listening
        webServer.start();
        
        trace('Server running at http://${webServer.getHost()}:${webServer.getPort()}');
    }
    
    public function update() {
        // Process requests (required for SnakeServer)
        webServer.handleRequest();
    }
    
    public function shutdown() {
        webServer.stop();
    }
}
```

### Switching Between Implementations

#### Using SnakeServer (Default - HashLink target)

```haxe
// In Main.hx
webServer = WebServerFactory.create(
    WebServerType.SnakeServer,
    "127.0.0.1",
    8000,
    SideWinderRequestHandler,
    "static"  // Optional static file directory
);
```

**Pros:**
- Well-tested with SideWinder
- Full feature support
- Works with HashLink

**Cons:**
- HashLink specific
- May have higher memory overhead

#### Using CivetWeb (HashLink with native .hdll)

```bash
# First, build the native library
./build_civetweb.sh
```

```haxe
webServer = WebServerFactory.create(
    WebServerType.CivetWeb,
    "127.0.0.1",
    8000,
    null,  // Not used by CivetWeb
    "static"  // Optional static file directory
);
```

**Pros:**
- Native C performance
- Lightweight and fast
- Cross-platform
- Works with HashLink target
- Threaded request handling

**Cons:**
- Requires building native .hdll
- Additional build step needed

### Configuration via Compile Flags

You can configure the server type at compile time using defines in `project.xml`:

```xml
<!-- Use CivetWeb on cpp target -->
<define name="use_civetweb" if="cpp" />
```

Then in code:

```haxe
var serverType = #if use_civetweb WebServerType.CivetWeb #else WebServerType.SnakeServer #end;
webServer = WebServerFactory.create(serverType, host, port, handlerClass);
```

## Implementation Details

### SnakeServerAdapter

Wraps the `snake-server` HTTP server implementation with single-threaded queue:

- **Threading:** Snake-server threads accept connections, queue requests
- **Processing:** Single-threaded via main loop
- **Protocol:** HTTP/1.0 and HTTP/1.1
- **Features:** Full request/response handling, custom request handlers
- **Target:** HashLink (hl)
- **Queue:** Mutex-protected for thread safety

### CivetWebAdapter

Wraps CivetWeb C library via HashLink native bindings:

- **Threading:** Native threaded implementation
- **Protocol:** HTTP/1.0, HTTP/1.1
- **Features:** Embedded web server, callbacks to Haxe
- **Target:** HashLink (hl)
- **Status:** Production ready
- **Native Library:** `civetweb.hdll` (build with `./build_civetweb.sh`)

## Adding New Server Implementations

To add a new web server implementation:

1. **Create an adapter class** implementing `IWebServer`:

```haxe
package sidewinder;

class MyServerAdapter implements IWebServer {
    private var host:String;
    private var port:Int;
    private var running:Bool = false;
    
    public function new(host:String, port:Int) {
        this.host = host;
        this.port = port;
    }
    
    public function start():Void {
        // Initialize and start your server
        running = true;
    }
    
    public function handleRequest():Void {
        // Process pending requests
    }
    
    public function stop():Void {
        // Clean up and stop
        running = false;
    }
    
    public function getHost():String return host;
    public function getPort():Int return port;
    public function isRunning():Bool return running;
}
```

2. **Add to WebServerType enum**:

```haxe
enum WebServerType {
    SnakeServer;
    CivetWeb;
    MyServer;  // Add here
}
```

3. **Update WebServerFactory**:

```haxe
public static function create(...):IWebServer {
    return switch (type) {
        case SnakeServer: new SnakeServerAdapter(...);
        case CivetWeb: new CivetWebAdapter(...);
        case MyServer: new MyServerAdapter(...);
    };
}
```

## Troubleshooting

### SnakeServer Issues

**Problem:** Server not responding
- Ensure `handleRequest()` is called regularly in your main loop
- Check that `SideWinderRequestHandler` is properly configured
- Verify the port is not already in use

**Problem:** Protocol version errors
- Set `BaseHTTPRequestHandler.protocolVersion = "HTTP/1.0"` for compatibility

### CivetWeb Issues

**Problem:** "civetweb.hdll not found"
- Build the native library: `./build_civetweb.sh`
- Or manually: `cd native/civetweb && make && make install`
- Verify civetweb.hdll exists in Export/hl/bin/

**Problem:** Build fails with "hl.h not found"
- Install HashLink development headers
- Update HL_INCLUDE path in native/civetweb/Makefile
- Linux: `apt install hashlink-dev` or build from source

**Problem:** Server starts but requests fail
- Check request handler is properly configured
- Verify callbacks are working (check logs)
- Ensure Router is initialized before server starts

### General Issues

**Problem:** Port already in use
```haxe
try {
    webServer.start();
} catch (e:Dynamic) {
    trace('Failed to start server: $e');
    // Try alternative port
}
```

**Problem:** Server crashes on stop
- Ensure `stop()` is only called once
- Check all resources are properly cleaned up

## Performance Considerations

### SnakeServer
- **Memory:** Moderate - uses Haxe threads
- **Throughput:** Good for most use cases
- **Latency:** Low for small payloads
- **Best for:** Development, moderate traffic applications

### CivetWeb
- **Memory:** Low - native C implementation
- **Throughput:** Excellent - optimized C code
- **Latency:** Very low
- **Best for:** Production, high-traffic applications, embedded systems

## Future Enhancements

- [ ] Complete haxelib-civetweb bindings
- [ ] Add HTTP/2 support
- [ ] WebSocket support for SnakeServer
- [ ] Add more server implementations (uv, libuv-based)
- [ ] Performance benchmarking suite
- [ ] SSL/TLS support for SnakeServer

## See Also

- [snake-server on Haxelib](https://lib.haxe.org/p/snake-server)
- [CivetWeb GitHub](https://github.com/civetweb/civetweb)
- [Main.hx](Source/Main.hx) - Example usage
- [POLLING_README.md](POLLING_README.md) - Message broker documentation
