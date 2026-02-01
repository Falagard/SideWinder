# SideWinder

A Haxe-based web framework with flexible HTTP server support, dependency injection, and async client capabilities.

## Features

- **Multiple Web Server Support**: Swap between SnakeServer (default) and CivetWeb implementations
- **Dependency Injection**: Built-in DI container for service management
- **Auto-generated REST Clients**: Synchronous and asynchronous client generation from interfaces
- **Database Migrations**: SQL migration support
- **Routing**: Automatic and manual routing capabilities
- **Message Broker**: Long-polling message broker implementation

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

## Project Structure

- `Source/Main.hx` - Application entry point
- `Source/sidewinder/` - Core framework code
  - `IWebServer.hx` - Web server abstraction
  - `WebServerFactory.hx` - Factory for creating servers
  - `SnakeServerAdapter.hx` - SnakeServer implementation
  - `CivetWebAdapter.hx` - CivetWeb implementation
  - `Router.hx` - HTTP routing
  - `DI.hx` - Dependency injection
- `static/` - Static web assets
- `migrations/` - Database migrations

## Documentation

- [WEB_SERVER_GUIDE.md](WEB_SERVER_GUIDE.md) - Web server abstraction guide
- [POLLING_README.md](POLLING_README.md) - Long-polling message broker
- [HTML5_GUIDE.md](HTML5_GUIDE.md) - HTML5 target guide




