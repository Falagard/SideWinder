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

### 2. **CivetWeb** (Experimental)
- **Target:** C++ (cpp)
- **Description:** Lightweight, embeddable C web server
- **Characteristics:**
  - Native C implementation
  - Very lightweight and fast
  - Cross-platform (Windows, Linux, macOS)
  - Requires native bindings (in development)

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

#### Using CivetWeb (C++ target)

```haxe
#if cpp
webServer = WebServerFactory.create(
    WebServerType.CivetWeb,
    "127.0.0.1",
    8000,
    null,  // Not used by CivetWeb
    "static"  // Optional static file directory
);
#end
    8000,
    SideWinderRequestHandler,
    "./static"
);

// Automatic selection based on target
var server = WebServerFactory.createDefault(
    "127.0.0.1",
    8000,
    SideWinderRequestHandler,
    "./static"