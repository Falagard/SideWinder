# Copilot Instructions for SideWinder

## Project Overview
- **Language/Platform:** Haxe, targeting HashLink (hl)
- **Main App Entry:** `Source/Main.hx` and `sidewinder/SideWinderServer.hx`
- **Core Logic:** Resides in `Source/sidewinder/` (e.g., `App.hx`, `Router.hx`, `IDatabaseService.hx`)
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
- **Dependency Injection:**
  - Services (e.g., `UserService`, `CacheService`, `DatabaseService`) are injected via `DI.hx`.
- **Routing:**
  - HTTP routing logic is in `Router.hx` and `AutoRouter.hx`.
- **Database:**
  - Database access via `IDatabaseService` interface with implementations: `SqliteDatabaseService`, `MySqlDatabaseService`
  - Migrations in `migrations/`, see `DATABASE_BACKENDS.md` for details.
- **Logging:**
  - Use `HybridLogger.hx` for logging; logs output to `Export/hl/bin/logs/`.
- **Interfaces:**
  - Service contracts defined as `I*` (e.g., `ICacheService.hx`, `IDatabaseService.hx`).

## Integration Points
- **External Libraries:**
  - Native libraries in `Export/hl/bin/*.hdll` (e.g., `mysql.hdll`, `ssl.hdll`)
- **Postman Collections:**
  - API tests in `SideWinder.postman_collection.json` and environment in `SideWinder.postman_environment.json`

## Examples
- **Add a new service:**
  - Define interface in `IServiceName.hx`, implement in `ServiceName.hx`, register in `DI.hx`.
- **Add a route:**
  - Update `Router.hx` and/or `AutoRouter.hx` with new handler.
- **Switch database backend:**
  - Update DI configuration in `Main.hx` to use `SqliteDatabaseService` or `MySqlDatabaseService`.

## Tips
- **Do not modify files in `Export/hl/bin/` directly.**
- **Follow Haxe idioms for type safety and pattern matching.**
- **Check `README.md` for up-to-date build instructions.**
