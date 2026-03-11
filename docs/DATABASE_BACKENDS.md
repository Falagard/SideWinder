# Database Backend Support

SideWinder now supports multiple database backends through a service interface pattern. This allows you to easily switch between different database implementations without changing your application code.

## Supported Backends

### 1. SQLite (Default)
- **Implementation:** `SqliteDatabaseService`
- **Use Case:** Development, small deployments, single-file database
- **Configuration:** No additional configuration needed
- **File Location:** `data.db` in the application root

### 2. MySQL
- **Implementation:** `MySqlDatabaseService`
- **Use Case:** Production, multi-user, distributed deployments
- **Configuration:** Requires connection parameters

## Configuration

### Using SQLite (Default)

In `Main.hx`, configure DI to use SQLite:

```haxe
DI.init(c -> {
    // Use SQLite (default)
    c.addSingleton(IDatabaseService, SqliteDatabaseService);
    
    c.addScoped(IUserService, UserService);
    c.addSingleton(ICacheService, InMemoryCacheService);
    c.addSingleton(IMessageBroker, PollingMessageBroker);
    c.addSingleton(IStreamBroker, LocalStreamBroker);
});
```

### Using MySQL

To use MySQL instead, update your `Main.hx`:

```haxe
DI.init(c -> {
    // Configure MySQL with connection parameters
    c.addSingleton(IDatabaseService, () -> {
        return new MySqlDatabaseService(
            "localhost",    // host
            3306,           // port
            "sidewinder",   // database name
            "root",         // username
            "password"      // password
        );
    });
    
    c.addScoped(IUserService, UserService);
    c.addSingleton(ICacheService, InMemoryCacheService);
    c.addSingleton(IMessageBroker, PollingMessageBroker);
    c.addSingleton(IStreamBroker, LocalStreamBroker);
});
```

Or use environment variables:

```haxe
DI.init(c -> {
    // Configure MySQL from environment variables
    c.addSingleton(IDatabaseService, () -> {
        return new MySqlDatabaseService(
            Sys.getEnv("DB_HOST") ?? "localhost",
            Std.parseInt(Sys.getEnv("DB_PORT") ?? "3306"),
            Sys.getEnv("DB_NAME") ?? "sidewinder",
            Sys.getEnv("DB_USER") ?? "root",
            Sys.getEnv("DB_PASS") ?? ""
        );
    });
    
    // ... other services
});
```

## Database Service Interface

All database implementations must implement the `IDatabaseService` interface:

```haxe
interface IDatabaseService extends Service {
    public function acquire():Connection;
    public function release(conn:Connection):Void;
    public function requestWithParams(sql:String, ?params:Map<String, Dynamic>):ResultSet;
    public function execute(sql:String, ?params:Map<String, Dynamic>):Void;
    public function runMigrations():Void;
    public function buildSql(sql:String, params:Map<String, Dynamic>):String;
    public function escapeString(str:String):String;
    public function quoteString(str:String):String;
    public function sanitize(str:String):String;
    public function raw(v:String):RawSql;
}
```

## Using the Database Service

Services that need database access should inject `IDatabaseService`:

```haxe
class MyService implements IMyService {
    var db:IDatabaseService;

    public function new() {
        db = DI.get(IDatabaseService);
    }

    public function getData():Array<Data> {
        var result:Array<Data> = [];
        var rs = db.requestWithParams("SELECT * FROM data WHERE id = @id", ["id" => 123]);
        while (rs.hasNext()) {
            var r = rs.next();
            result.push({ id: r.id, name: r.name });
        }
        return result;
    }
}
```

## Migrations

SideWinder supports **per-backend migrations** to accommodate SQL syntax differences between databases. The migration system:

1. Creates a `migrations` table to track applied migrations
2. Reads all `.sql` files from the backend-specific directory:
   - SQLite: `migrations/sqlite/`
   - MySQL: `migrations/mysql/`
3. Applies migrations in alphabetical order
4. Records each migration in the `migrations` table

### Migration Directory Structure

```
migrations/
├── sqlite/
│   └── 2025102401-initial.sql    # SQLite-specific syntax
└── mysql/
    └── 2025102401-initial.sql    # MySQL-specific syntax
```

### Naming Convention

Use descriptive filenames with timestamps or version numbers:
- `YYYYMMDDNN-description.sql` (e.g., `2025102401-initial.sql`)
- Migrations are applied in alphabetical order
- Each backend maintains its own migration history

### Running Migrations

Migrations are automatically run when the application starts:

```haxe
var db = DI.get(IDatabaseService);
db.runMigrations();
```

### Example: SQLite vs MySQL Migrations

**SQLite** (`migrations/sqlite/2025102401-initial.sql`):
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT (datetime('now'))
);
```

**MySQL** (`migrations/mysql/2025102401-initial.sql`):
```sql
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Key Differences to Note

| Feature | SQLite | MySQL |
|---------|--------|-------|
| Auto-increment | `INTEGER PRIMARY KEY AUTOINCREMENT` | `INT AUTO_INCREMENT PRIMARY KEY` |
| String type | `TEXT` | `VARCHAR(n)` or `TEXT` |
| Datetime | `DATETIME DEFAULT (datetime('now'))` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

## Connection Pooling

Both SQLite and MySQL implementations use connection pooling:
- **Pool Size:** 8 connections maximum (configurable via `MAX_POOL_SIZE`)
- **Acquire:** Gets a connection from the pool or creates a new one
- **Release:** Returns a connection to the pool for reuse

Example of direct connection usage:

```haxe
var conn = db.acquire();
try {
    var rs = conn.request("SELECT * FROM users");
    while (rs.hasNext()) {
        var user = rs.next();
        trace(user.name);
    }
} finally {
    db.release(conn);
}
```

## SQL Parameter Binding

Use named parameters for safe SQL queries:

```haxe
var params = new Map<String, Dynamic>();
params.set("email", "user@example.com");
params.set("name", "John Doe");

db.execute("INSERT INTO users (email, name) VALUES (@email, @name)", params);
```

## Important Notes

### SQLite-specific
- Uses `last_insert_rowid()` to get auto-increment IDs
- Uses `changes()` to get affected rows count
- Enables WAL mode and foreign keys by default

### MySQL-specific
- Uses `LAST_INSERT_ID()` to get auto-increment IDs
- Uses `ROW_COUNT()` to get affected rows count
- Note: Current `UserService` implementation uses SQLite-specific functions (`last_insert_rowid()`, `changes()`) that need updating for full MySQL compatibility

### Updating UserService for MySQL Compatibility

To make `UserService` fully compatible with MySQL, update the database-specific function calls:

**For getting last insert ID:**
```haxe
// SQLite
var rs = conn.request("SELECT last_insert_rowid() AS id");

// MySQL
var rs = conn.request("SELECT LAST_INSERT_ID() AS id");
```

**For getting affected rows:**
```haxe
// SQLite
var rs = conn.request("SELECT changes() AS affected");

// MySQL
var rs = conn.request("SELECT ROW_COUNT() AS affected");
```

Consider creating database-agnostic methods in `IDatabaseService` for these operations:
```haxe
public function getLastInsertId():Int;
public function getAffectedRows():Int;
```

## Creating Custom Backends

To add support for another database (PostgreSQL, SQL Server, etc.):

1. Create a new class implementing `IDatabaseService`
2. Implement all required methods
3. Register it in the DI container in `Main.hx`

Example:

```haxe
class PostgreSqlDatabaseService implements IDatabaseService {
    // Implement all interface methods
}

// In Main.hx:
DI.init(c -> {
    c.addSingleton(IDatabaseService, PostgreSqlDatabaseService);
});
```

## Architecture Benefits

This abstraction provides:
- **Flexibility:** Switch databases without code changes
- **Testability:** Mock database for unit tests
- **Maintainability:** Database logic isolated in service layer
- **Scalability:** Easy to add new database backends
