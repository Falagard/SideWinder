# SideWinder Development Patterns

Established patterns and best practices for extending the SideWinder system.

## Authentication Patterns

### API Key Security
- **Hashing**: NEVER store API keys in plaintext. Use `sidewinder.data.AuthUtils.hashApiKey()` (SHA-256) before storing in the database.
- **Metadata**: Store the key `prefix` and `last_four` digits for identification in UIs without compromising security.
- **Headers**: Implement API key authentication via the `X-API-KEY` header.

### Middleware Flow
1. Check for `X-API-KEY`.
2. check for `Authorization: Bearer <token>`.
3. Check for `auth_token` cookie.
4. Populate `AuthContext` on the request object.

## Database Patterns

### Migrations
- All schema changes must be added as `.sql` files in `migrations/sqlite/` (or the appropriate backend folder).
- Use timestamped filenames (e.g., `YYYYMMDDHH-description.sql`).

### Write Batching
- Use `IDatabaseService.execute()` for single writes.
- For high-volume writes, leverage the background writer thread implementation in `SqliteDatabaseService` to avoid SQLite locking issues.

## Routing Patterns

### Interface Metadata
- Define API endpoints on interfaces in `sidewinder.interfaces`.
- Use `@get("/path")`, `@post("/path")` etc.
- Use `@requiresPermission("permission_name")` for access control.
- Use `@noAuth` to skip authentication for public endpoints.

## Dependency Injection
- Always register services in `Main.hx` or appropriate bootstrap: `DI.register(IInterface, implementation)`.
- Resolve services using `DI.get(IInterface)`.
