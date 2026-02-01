# SideWinder

A Haxe-based web framework with flexible HTTP server support, dependency injection, and async client capabilities.

## Features

- **Multiple Web Server Support**: Swap between SnakeServer (default) and CivetWeb implementations
- **WebSocket Support**: Real-time bidirectional communication with multiple handler examples
- **Dependency Injection**: Built-in DI container for service management
- **Auto-generated REST Clients**: Synchronous and asynchronous client generation from interfaces
- **Database Migrations**: SQL migration support
- **Routing**: Automatic and manual routing capabilities
- **Message Broker**: Long-polling message broker for real-time updates
- **Stream Broker**: Fire-and-forget message handling with consumer groups (Redis Streams compatible)
- **File Upload**: Multipart form data handling with file system storage

## Quick Start

### Prerequisites

Install Haxe Module Manager (hmm):

```bash
haxelib --global install hmm
haxelib --global run hmm setup
```

### Installation

Run the following in the project directory:

```bash
hmm install
```

### Running

```bash
lime test hl
```

## Web Server Configuration

SideWinder supports multiple HTTP server backends. See [WEB_SERVER_GUIDE.md](WEB_SERVER_GUIDE.md) for details.

### Default (SnakeServer)

```haxe
var webServer = WebServerFactory.create(
    WebServerType.SnakeServer,
    "127.0.0.1",
    8000,
    SideWinderRequestHandler
);
```

### CivetWeb (HashLink with native bindings)

```bash
# Build native library first
./build_civetweb.sh
```

```haxe
var webServer = WebServerFactory.create(
    WebServerType.CivetWeb,
    "127.0.0.1",
    8000
);
```

## WebSocket Support

SideWinder includes comprehensive WebSocket support via CivetWeb. See [WEBSOCKET_GUIDE.md](WEBSOCKET_GUIDE.md) for details.

### WebSocket Handler Examples

Choose from multiple WebSocket handler implementations in `Main.hx`:

```haxe
// In Main.hx, change wsHandlerType to select a handler:
var wsHandlerType = "chat"; // Options: "echo", "chat", "broadcast", "auth"
```

**Available Handlers:**

1. **Echo Handler** (`EchoWebSocketHandler`)
   - Simple echo server that reflects messages back
   - Test at: `http://localhost:8000/websocket_test.html`

2. **Chat Room Handler** (`ChatRoomWebSocketHandler`)
   - Multi-user chat room with user management
   - Join/leave notifications and user lists
   - Test at: `http://localhost:8000/chatroom_demo.html`

3. **Broadcast Handler** (`BroadcastWebSocketHandler`)
   - Channel-based pub/sub messaging
   - Subscribe to multiple channels
   - Test at: `http://localhost:8000/broadcast_demo.html`

4. **Authenticated Handler** (`AuthenticatedWebSocketHandler`)
   - Token-based authentication required
   - Demo tokens: `demo-token-123`, `admin-token-456`
   - Test at: `http://localhost:8000/auth_demo.html`

### Quick WebSocket Test

```bash
# 1. Build CivetWeb native library
./build_civetweb.sh

# 2. Run server
lime test hl

# 3. Open test page in browser
# http://localhost:8000/websocket_test.html
```

## Project Structure

- `Source/Main.hx` - Application entry point
- `Source/sidewinder/` - Core framework code
  - `IWebServer.hx` - Web server abstraction
  - `WebServerFactory.hx` - Factory for creating servers
  - `SnakeServerAdapter.hx` - SnakeServer implementation
  - `CivetWebAdapter.hx` - CivetWeb implementation
  - `Router.hx` - HTTP routing
  - `DI.hx` - Dependency injection
  - **WebSocket Handlers:**
    - `IWebSocketHandler.hx` - WebSocket handler interface
    - `EchoWebSocketHandler.hx` - Echo server
    - `ChatRoomWebSocketHandler.hx` - Multi-user chat
    - `BroadcastWebSocketHandler.hx` - Channel broadcasting
    - `AuthenticatedWebSocketHandler.hx` - Authenticated connections
- `static/` - Static web assets
  - `websocket_test.html` - Echo test client
  - `chatroom_demo.html` - Chat room client
  - `broadcast_demo.html` - Broadcast client
  - `auth_demo.html` - Authenticated client
  - `upload_test.html` - File upload test
- `migrations/` - Database migrations
- `native/civetweb/` - CivetWeb native bindings

## Documentation

- [WEB_SERVER_GUIDE.md](WEB_SERVER_GUIDE.md) - Web server abstraction guide
- [WEBSOCKET_GUIDE.md](WEBSOCKET_GUIDE.md) - WebSocket implementation and examples
- [POLLING_README.md](POLLING_README.md) - Long-polling message broker
- [STREAM_BROKER_GUIDE.md](STREAM_BROKER_GUIDE.md) - Stream broker system (fire-and-forget, consumer groups)
- [MESSAGING_SYSTEMS_COMPARISON.md](MESSAGING_SYSTEMS_COMPARISON.md) - Comparison of all messaging systems
- [HTML5_GUIDE.md](HTML5_GUIDE.md) - HTML5 target guide
- [CIVETWEB_INTEGRATION.md](CIVETWEB_INTEGRATION.md) - CivetWeb integration details
- [SINGLE_THREADED_ARCHITECTURE.md](SINGLE_THREADED_ARCHITECTURE.md) - Threading model




