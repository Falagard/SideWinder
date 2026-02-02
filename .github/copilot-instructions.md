# Copilot Instructions for SideWinder

## Project Overview
- **Language/Platform:** Haxe, targeting HashLink (hl)
- **Main App Entry:** `Source/Main.hx`
- **Core Logic:** Resides in `Source/sidewinder/` (e.g., `App.hx`, `Router.hx`, `IDatabaseService.hx`, `SideWinderServer.hx`, `SideWinderRequestHandler.hx`)
- **Static Assets:** Served from `static/` and `Export/hl/static/`
- **Migrations:** SQL files in `migrations/` and `Export/hl/migrations/`

## Build & Run Workflow
- **Dependency Management:**
  - Use [Haxe Module Manager (hmm)](https://github.com/haxetink/hmm)
  - Install globally: `haxelib --global install hmm && haxelib --global run hmm setup`
  - In project root: `hmm install`
- **Build/Run:**
  - Run: `lime test hl` (compiles and runs the HashLink target)
- **Artifacts:**
  - Output in `Export/hl/bin/` (dlls, logs, etc.)

## Key Patterns & Conventions
- **Async Patterns:**
  - Async logic is handled in files like `AutoClientAsync.hx` using callback or promise-like patterns.
  - `AsyncBlockerPool.hx` handles blocking async operations in request threads.
- **Dependency Injection:**
  - Services (e.g., `UserService`, `CacheService`, `DatabaseService`, `AuthService`, `OAuthService`) are injected via `DI.hx`.
  - Register services in `Main.hx` DI initialization.
- **Routing:**
  - HTTP routing logic is in `Router.hx` and `AutoRouter.hx`.
  - Middleware support via `App.hx` (Express-like pattern).
  - Authentication middleware in `AuthMiddleware.hx`.
- **Database:**
  - Database access via `IDatabaseService` interface with implementations: `SqliteDatabaseService`, `MySqlDatabaseService`
  - Migrations in `migrations/`, see `DATABASE_BACKENDS.md` for details.
  - Connection pooling and parameter binding supported.
- **Caching:**
  - Cache services via `ICacheService` interface.
  - Implementations: `InMemoryCacheService` (production-ready, thread-safe with LRU), `RedisCacheService` (placeholder).
  - See `CACHE_SYSTEM.md` for details.
- **Authentication & OAuth:**
  - Token-based authentication via `IAuthService` and `AuthService`.
  - OAuth integration via `IOAuthService` and `OAuthService`.
  - Supports Google, GitHub, Microsoft, and custom providers.
  - OAuth flow endpoints in `OAuthController.hx`.
  - See `AUTH_README.md` and OAuth documentation for details.
- **WebSockets:**
  - WebSocket support via `CivetWebAdapter` with multiple handler implementations.
  - Handlers: `EchoWebSocketHandler`, `ChatRoomWebSocketHandler`, `BroadcastWebSocketHandler`, `AuthenticatedWebSocketHandler`.
  - See `WEBSOCKET_GUIDE.md` for details.
- **Messaging Systems:**
  - Long-polling: `IMessageBroker` with `PollingMessageBroker`.
  - Stream broker: `IStreamBroker` with `LocalStreamBroker` (Redis Streams compatible).
  - See `MESSAGING_SYSTEMS_COMPARISON.md` for system comparison.
- **Logging:**
  - Use `HybridLogger.hx` for logging; logs output to `Export/hl/bin/logs/`.
  - Multiple providers: `FileLogProvider`, `SqliteLogProvider`, `SeqLogProvider`.
  - Supports log levels: DEBUG, INFO, WARN, ERROR, FATAL.
  - See `SEQ_LOGGING_GUIDE.md` for Seq integration.
- **Notifications:**
  - Email notifications via `INotificationService` and `SendGridNotificationService`.
  - Configure with `SENDGRID_API_KEY` and `SENDGRID_FROM_EMAIL` environment variables.
  - See `NOTIFICATION_SYSTEM.md` for details.
- **Interfaces:**
  - Service contracts defined as `I*` (e.g., `ICacheService.hx`, `IDatabaseService.hx`, `IAuthService.hx`).

## Integration Points
- **External Libraries:**
  - Native libraries in `Export/hl/bin/*.hdll` (e.g., `mysql.hdll`, `ssl.hdll`)
- **Postman Collections:**
  - API tests in `SideWinder.postman_collection.json` and environment in `SideWinder.postman_environment.json`

## Examples
- **Add a new service:**
  - Define interface in `IServiceName.hx`, implement in `ServiceName.hx`, register in `DI.hx` (via `Main.hx`).
  - Example: `IUserService` → `UserService` → register as `c.addScoped(IUserService, UserService)`.
- **Add a route:**
  - Update `Router.hx` with `router.add()` or use `App.get()`, `App.post()`, etc.
  - For auto-generated routes: use `AutoRouter.build()` with a service interface.
- **Switch database backend:**
  - Update DI configuration in `Main.hx` to use `SqliteDatabaseService` or `MySqlDatabaseService`.
  - For MySQL: `c.addSingleton(IDatabaseService, () -> new MySqlDatabaseService(host, port, db, user, pass))`.
- **Add OAuth provider:**
  - Configure provider in `OAuthConfigSetup.hx` or environment variables.
  - Providers: Google, GitHub, Microsoft, custom.
  - See `AUTH_README.md` for setup instructions.
- **Add WebSocket handler:**
  - Implement `IWebSocketHandler` interface.
  - Register in `Main.hx` with `civetAdapter.setWebSocketHandler(handler)`.
- **Add cache service:**
  - Inject `ICacheService` and use `set()`, `get()`, `getOrCompute()` methods.
  - Default: `InMemoryCacheService` (thread-safe with LRU).
- **Send email:**
  - Inject `INotificationService` and use `sendEmail()` method.
  - Configure SendGrid API key via environment variables.

## Tips
- **Do not modify files in `Export/hl/bin/` directly.**
- **Follow Haxe idioms for type safety and pattern matching.**
- **Check `README.md` for up-to-date build instructions.**
