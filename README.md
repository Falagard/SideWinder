# SideWinder

A Haxe-based web framework with flexible HTTP server support, dependency injection, and async client capabilities.

## Features

- **Multiple Web Server Support**: Swap between SnakeServer (default) and CivetWeb implementations
- **WebSocket Support**: Real-time bidirectional communication with multiple handler examples
- **Dependency Injection**: Built-in DI container for service management
- **Auto-generated REST Clients**: Synchronous and asynchronous client generation from interfaces
- **Database Support**: Multiple database backends (SQLite, MySQL) with migration support
- **Routing**: Automatic and manual routing capabilities with middleware support
- **Message Broker**: Long-polling message broker for real-time updates
- **Stream Broker**: Fire-and-forget message handling with consumer groups (Redis Streams compatible)
- **File Upload**: Multipart form data handling with file system storage
- **Caching System**: Thread-safe in-memory caching with LRU eviction and optional Redis support
- **Logging System**: Hybrid logging with multiple providers (File, SQLite, Seq)
- **Authentication & OAuth**: Token-based authentication with OAuth provider support (Google, GitHub, Microsoft)
- **Email Notifications**: SendGrid integration for email sending
- **Stripe Subscriptions**: Stripe Checkout subscriptions with webhook handling and recurring billing logs

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

The server will start on `http://127.0.0.1:8000` by default.

### Configuration

For optional features like email notifications and OAuth authentication, configure environment variables. See [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) for a complete reference.

## Stripe Subscriptions

SideWinder includes Stripe Checkout-based subscription support with webhook processing and recurring billing logs.

### Endpoints

- `POST /stripe/checkout-session` — Create a Stripe Checkout Session for subscriptions.
  - Body: `userId`, `priceId` (optional if `STRIPE_PRICE_ID` is set), `successUrl`, `cancelUrl`
- `GET /stripe/subscription/:userId` — Fetch subscription status for a user.
- `POST /stripe/cancel-subscription` — Cancel a user subscription.
  - Body: `userId`
- `POST /stripe/webhooks` — Stripe webhook receiver.

### Required Environment Variables

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- Optional: `STRIPE_PRICE_ID`

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
  - **Web Servers:**
    - `IWebServer.hx` - Web server abstraction
    - `WebServerFactory.hx` - Factory for creating servers
    - `SnakeServerAdapter.hx` - SnakeServer implementation
    - `CivetWebAdapter.hx` - CivetWeb implementation
  - **Routing & Middleware:**
    - `Router.hx` - HTTP routing
    - `AutoRouter.hx` - Automatic route generation
    - `App.hx` - Express-like middleware and routing
    - `AuthMiddleware.hx` - Authentication middleware
  - **Dependency Injection:**
    - `DI.hx` - Dependency injection container
  - **WebSocket Handlers:**
    - `IWebSocketHandler.hx` - WebSocket handler interface
    - `EchoWebSocketHandler.hx` - Echo server
    - `ChatRoomWebSocketHandler.hx` - Multi-user chat
    - `BroadcastWebSocketHandler.hx` - Channel broadcasting
    - `AuthenticatedWebSocketHandler.hx` - Authenticated connections
  - **Database Services:**
    - `IDatabaseService.hx` - Database service interface
    - `SqliteDatabaseService.hx` - SQLite implementation
    - `MySqlDatabaseService.hx` - MySQL implementation
    - `Database.hx` - Database utilities
  - **Cache Services:**
    - `ICacheService.hx` - Cache service interface
    - `InMemoryCacheService.hx` - Thread-safe in-memory cache with LRU
    - `RedisCacheService.hx` - Redis cache (template/placeholder)
  - **Authentication & OAuth:**
    - `IAuthService.hx` - Authentication service interface
    - `AuthService.hx` - Session and token management
    - `IOAuthService.hx` - OAuth service interface
    - `OAuthService.hx` - OAuth provider integration
    - `OAuthController.hx` - OAuth flow endpoints
    - `OAuthConfigSetup.hx` - OAuth configuration helpers
    - `DesktopOAuthClient.hx` - Desktop OAuth client
    - `DeviceFlowOAuthClient.hx` - Device flow OAuth
    - `SecureTokenStorage.hx` - Secure token storage
  - **Messaging Systems:**
    - `IMessageBroker.hx` - Message broker interface
    - `PollingMessageBroker.hx` - Long-polling implementation
    - `IStreamBroker.hx` - Stream broker interface
    - `LocalStreamBroker.hx` - Local stream implementation
  - **Notification Services:**
    - `INotificationService.hx` - Notification service interface
    - `SendGridNotificationService.hx` - SendGrid email integration
  - **Logging:**
    - `HybridLogger.hx` - Multi-provider logging system
    - `ILogProvider.hx` - Log provider interface
    - `FileLogProvider.hx` - File-based logging with rotation
    - `SqliteLogProvider.hx` - SQLite logging with batching
    - `SeqLogProvider.hx` - Structured logging to Seq server
  - **Client Generation:**
    - `AutoClient.hx` - Synchronous REST client generator
    - `AutoClientAsync.hx` - Asynchronous REST client generator
  - **User Management:**
    - `IUserService.hx` - User service interface
    - `UserService.hx` - User management implementation
  - **Utilities:**
    - `CookieJar.hx` - Cookie management for clients
    - `ICookieJar.hx` - Cookie jar interface
    - `AsyncBlockerPool.hx` - Async operation handling
- `static/` - Static web assets
  - `hello.html` - Static file serving example
  - `websocket_test.html` - Echo WebSocket test client
  - `chatroom_demo.html` - Chat room client
  - `broadcast_demo.html` - Broadcast channel client
  - `auth_demo.html` - Authenticated WebSocket client
  - `upload_test.html` - File upload test
  - `polling_demo.html` - Long-polling message client
  - `stream_demo.html` - Stream broker demo
  - `email_demo.html` - Email sending demo
- `migrations/` - Database migration SQL files
- `native/civetweb/` - CivetWeb native bindings (C code)

## Documentation

- **Getting Started:**
  - [README.md](README.md) - This file
  - [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) - Environment variable configuration reference
- **Web Servers:**
  - [WEB_SERVER_GUIDE.md](WEB_SERVER_GUIDE.md) - Web server abstraction guide
  - [CIVETWEB_INTEGRATION.md](CIVETWEB_INTEGRATION.md) - CivetWeb integration details
  - [CIVETWEB_QUICKREF.md](CIVETWEB_QUICKREF.md) - CivetWeb quick reference
- **Real-Time Communication:**
  - [WEBSOCKET_GUIDE.md](WEBSOCKET_GUIDE.md) - WebSocket implementation and examples
  - [POLLING_README.md](POLLING_README.md) - Long-polling message broker
  - [STREAM_BROKER_GUIDE.md](STREAM_BROKER_GUIDE.md) - Stream broker system (fire-and-forget, consumer groups)
  - [MESSAGING_SYSTEMS_COMPARISON.md](MESSAGING_SYSTEMS_COMPARISON.md) - Comparison of all messaging systems
- **Data & Storage:**
  - [DATABASE_BACKENDS.md](DATABASE_BACKENDS.md) - Database service implementations (SQLite, MySQL)
  - [CACHE_SYSTEM.md](CACHE_SYSTEM.md) - Cache system architecture and implementations
- **Authentication & Security:**
  - [AUTH_README.md](AUTH_README.md) - Authentication middleware with OAuth support
  - [OAUTH_QUICK_START.md](OAUTH_QUICK_START.md) - Quick start guide for OAuth integration
  - [OAUTH_ARCHITECTURE.md](OAUTH_ARCHITECTURE.md) - OAuth system architecture
  - [OAUTH_API.md](OAUTH_API.md) - OAuth API reference
  - [OAUTH_REFERENCE_CARD.md](OAUTH_REFERENCE_CARD.md) - OAuth quick reference
  - [DESKTOP_OAUTH_GUIDE.md](DESKTOP_OAUTH_GUIDE.md) - Desktop OAuth client guide
- **Notifications & Logging:**
  - [NOTIFICATION_SYSTEM.md](NOTIFICATION_SYSTEM.md) - SendGrid email notification integration
  - [SEQ_LOGGING_GUIDE.md](SEQ_LOGGING_GUIDE.md) - Structured logging with Seq integration
- **Development:**
  - [HTML5_GUIDE.md](HTML5_GUIDE.md) - HTML5 target guide
  - [SINGLE_THREADED_ARCHITECTURE.md](SINGLE_THREADED_ARCHITECTURE.md) - Threading model
  - [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md) - Refactoring history and changes




