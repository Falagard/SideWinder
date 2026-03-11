# Seq Logging Integration

This document explains how to use the Seq logging integration in SideWinder.

## Overview

SideWinder now supports multiple logging providers through a flexible provider-based architecture:
- **FileLogProvider**: Writes logs to rotating daily log files
- **SqliteLogProvider**: Writes logs to SQLite database with batching
- **SeqLogProvider**: Sends structured logs to a Seq server

## What is Seq?

[Seq](https://datalust.co/seq) is a centralized logging service that accepts structured logs. It provides:
- Real-time log streaming
- Powerful search and filtering
- Log level management
- Dashboard and visualization
- API key-based authentication

## Quick Start

### 1. Install Seq (Optional)

If you want to use Seq logging, you need a Seq server running. You can:

**Option A: Use Docker (Recommended)**
```bash
docker run --name seq -d --restart unless-stopped -e ACCEPT_EULA=Y -p 5341:80 datalust/seq:latest
```

**Option B: Download from https://datalust.co/download**

Access Seq UI at: `http://localhost:5341`

### 2. Configure Logging in Your Application

In your `Main.hx` or initialization code:

```haxe
import sidewinder.HybridLogger;
import sidewinder.FileLogProvider;
import sidewinder.SqliteLogProvider;
import sidewinder.SeqLogProvider;

// Initialize logger
HybridLogger.init(HybridLogger.LogLevel.DEBUG);

// Add file logging
HybridLogger.addProvider(new FileLogProvider("logs"));

// Add SQLite logging
HybridLogger.addProvider(new SqliteLogProvider("logs", 20, 5.0));

// Add Seq logging
HybridLogger.addProvider(new SeqLogProvider(
    "http://localhost:5341",  // Seq server URL
    null,                      // API key (optional)
    10                         // Batch size
));

// Start logging
HybridLogger.info("Application started");
```

### 3. Use the Logger

```haxe
HybridLogger.debug("Debug information");
HybridLogger.info("Information message");
HybridLogger.warn("Warning message");
HybridLogger.error("Error occurred");
```

## Advanced Usage

### Structured Logging

You can add custom properties to your log entries for better searchability in Seq:

```haxe
var properties = new Map<String, Dynamic>();
properties.set("userId", "12345");
properties.set("action", "login");
properties.set("duration", 150);

HybridLogger.logWithProperties("INFO", "User logged in", properties);
```

In Seq, you can then search for logs like:
- `userId = "12345"`
- `action = "login" and duration > 100`

### Configuring Seq Provider

The `SeqLogProvider` constructor accepts several parameters:

```haxe
new SeqLogProvider(
    seqUrl,       // Required: "http://your-seq-server:5341"
    apiKey,       // Optional: API key for authentication
    batchSize,    // Optional: Number of logs to batch (default: 10)
    minLevel      // Optional: Minimum log level (default: "DEBUG")
)
```

Example with all options:

```haxe
var seqProvider = new SeqLogProvider(
    "http://seq.mycompany.com:5341",
    "my-api-key-here",
    20,      // Batch 20 logs before sending
    "INFO"   // Only send INFO and above to Seq
);
HybridLogger.addProvider(seqProvider);
```

### Multiple Providers with Different Levels

You can configure different minimum levels for different providers:

```haxe
// Global minimum level
HybridLogger.init(HybridLogger.LogLevel.DEBUG);

// File logging: all levels
HybridLogger.addProvider(new FileLogProvider("logs"));

// Seq logging: only INFO and above
HybridLogger.addProvider(new SeqLogProvider(
    "http://localhost:5341",
    null,
    10,
    "INFO"  // Only INFO, WARN, ERROR to Seq
));
```

### Dynamic Provider Management

```haxe
// Get provider count
var count = HybridLogger.getProviderCount();

// Clear all providers (useful for testing)
HybridLogger.clearProviders();

// Re-add providers
HybridLogger.addProvider(new FileLogProvider("logs"));
```

## Seq API Key Setup

To use API keys with Seq:

1. Open Seq UI: `http://localhost:5341`
2. Go to Settings → API Keys
3. Create a new API key
4. Copy the key and use it in your configuration:

```haxe
HybridLogger.addProvider(new SeqLogProvider(
    "http://localhost:5341",
    "your-api-key-here"
));
```

## Log Format

Seq receives logs in CLEF (Compact Log Event Format), which is newline-delimited JSON:

```json
{"@t":"2026-02-01","@l":"Information","@mt":"Application started","@i":"0"}
{"@t":"2026-02-01","@l":"Error","@mt":"Connection failed","@i":"1","userId":"123"}
```

Where:
- `@t`: Timestamp
- `@l`: Log level (Debug, Information, Warning, Error)
- `@mt`: Message template
- `@i`: Event ID
- Additional fields are custom properties

## Performance Considerations

### Batching

Seq logging uses batching to reduce HTTP overhead. Logs are sent when:
- The batch size is reached (default: 10 logs)
- The logger is shut down

### Async Behavior

All log providers run on a separate thread to avoid blocking your main application:
- Logs are queued immediately
- Provider operations happen asynchronously
- Your application continues without waiting

### Error Handling

If Seq is unavailable:
- Errors are traced but don't crash your application
- File and SQLite logging continue to work
- Logs are not retried (to prevent memory buildup)

## Troubleshooting

### Logs not appearing in Seq

1. Check Seq is running: `curl http://localhost:5341/api/events/raw`
2. Verify the URL in your configuration
3. Check minimum log level settings
4. Look for error traces in console

### Connection refused

```
SeqLogProvider: HTTP error: ...
```

- Ensure Seq is running and accessible
- Verify firewall settings
- Check the URL and port

### API Key issues

```
SeqLogProvider: Server returned status 401
```

- Verify the API key is correct
- Check the key hasn't expired in Seq
- Ensure the key has write permissions

## Migration from Old HybridLogger

If you were using the old `HybridLogger.init(enableSqlite, minLevel)`:

**Old code:**
```haxe
HybridLogger.init(true, HybridLogger.LogLevel.DEBUG);
```

**New code:**
```haxe
HybridLogger.init(HybridLogger.LogLevel.DEBUG);
HybridLogger.addProvider(new FileLogProvider("logs"));
HybridLogger.addProvider(new SqliteLogProvider("logs"));
```

## Example: Full Configuration

```haxe
import sidewinder.HybridLogger;
import sidewinder.FileLogProvider;
import sidewinder.SqliteLogProvider;
import sidewinder.SeqLogProvider;

class Main {
    public static function main() {
        // Initialize with DEBUG level
        HybridLogger.init(HybridLogger.LogLevel.DEBUG);
        
        // File logging for all levels
        HybridLogger.addProvider(new FileLogProvider("logs"));
        
        // SQLite for searchable local logs
        HybridLogger.addProvider(new SqliteLogProvider("logs", 20, 5.0));
        
        // Seq for centralized monitoring (only WARN and above)
        #if !debug
        HybridLogger.addProvider(new SeqLogProvider(
            Sys.getEnv("SEQ_URL"),
            Sys.getEnv("SEQ_API_KEY"),
            20,
            "WARN"
        ));
        #end
        
        HybridLogger.info("Application initialized");
        
        // Your application code...
        
        // Cleanup on shutdown
        HybridLogger.shutdown();
    }
}
```

## Testing Seq Integration

Create a simple test file:

```haxe
import sidewinder.HybridLogger;
import sidewinder.SeqLogProvider;

class SeqTest {
    public static function main() {
        HybridLogger.init(HybridLogger.LogLevel.DEBUG);
        HybridLogger.addProvider(new SeqLogProvider("http://localhost:5341"));
        
        HybridLogger.debug("Debug message");
        HybridLogger.info("Info message");
        HybridLogger.warn("Warning message");
        HybridLogger.error("Error message");
        
        var props = new Map<String, Dynamic>();
        props.set("user", "test");
        props.set("count", 42);
        HybridLogger.logWithProperties("INFO", "Test with properties", props);
        
        Sys.sleep(1); // Allow time for batched send
        HybridLogger.shutdown();
    }
}
```

Run and check Seq UI at `http://localhost:5341` to see your logs.

## References

- [Seq Documentation](https://docs.datalust.co/docs)
- [CLEF Format Specification](https://github.com/serilog/serilog-formatting-compact)
- [Seq API Reference](https://docs.datalust.co/reference/api-overview)
