package sidewinder;

import sys.thread.Thread;
import sys.thread.Deque;

enum abstract LogLevel(Int) from Int to Int {
    var DEBUG = 0;
    var INFO = 1;
    var WARN = 2;
    var ERROR = 3;
}

/**
 * Hybrid logger with support for multiple logging providers.
 * 
 * Providers can include:
 * - FileLogProvider: Write logs to rotating files
 * - SqliteLogProvider: Write logs to SQLite database
 * - SeqLogProvider: Send structured logs to Seq server
 * 
 * Example usage:
 * ```haxe
 * HybridLogger.init();
 * HybridLogger.addProvider(new FileLogProvider("logs"));
 * HybridLogger.addProvider(new SeqLogProvider("http://localhost:5341"));
 * HybridLogger.info("Application started");
 * ```
 */
class HybridLogger {
    static var queue = new Deque<LogEntry>();
    static var workerStarted = false;
    static var stopRequested = false;
    static var providers:Array<ILogProvider> = [];
    static var minLevel:LogLevel = LogLevel.DEBUG;

    /**
     * Initialize the logger with optional minimum log level.
     * @param minLvl Minimum log level to process (default: INFO)
     */
    public static function init(?minLvl:LogLevel = INFO) {
        if (workerStarted) return;
        workerStarted = true;
        minLevel = minLvl;

        Thread.create(() -> {
            while (!stopRequested) {
                var entry = queue.pop(true);
                if (entry == null) continue;

                // Send to all registered providers
                for (provider in providers) {
                    try {
                        provider.log(entry);
                    } catch (e:Dynamic) {
                        trace('HybridLogger: Provider error: $e');
                    }
                }
            }

            // Shutdown all providers
            for (provider in providers) {
                try {
                    provider.shutdown();
                } catch (e:Dynamic) {
                    trace('HybridLogger: Provider shutdown error: $e');
                }
            }
        });
    }

    /**
     * Add a logging provider to receive log entries.
     * @param provider The log provider to add
     */
    public static function addProvider(provider:ILogProvider):Void {
        providers.push(provider);
    }

    /**
     * Remove all providers (useful for testing or reconfiguration).
     */
    public static function clearProviders():Void {
        providers = [];
    }

    /**
     * Get the current number of registered providers.
     */
    public static function getProviderCount():Int {
        return providers.length;
    }

    public static inline function debug(msg:String) log("DEBUG", LogLevel.DEBUG, msg);
    public static inline function info(msg:String)  log("INFO", LogLevel.INFO, msg);
    public static inline function warn(msg:String)  log("WARN", LogLevel.WARN, msg);
    public static inline function error(msg:String) log("ERROR", LogLevel.ERROR, msg);

    /**
     * Log a message with custom properties (for structured logging).
     * @param level Log level string
     * @param msg Message to log
     * @param properties Optional key-value properties for structured logging
     */
    public static function logWithProperties(level:String, msg:String, properties:Map<String, Dynamic>):Void {
        var lvl = switch (level.toUpperCase()) {
            case "DEBUG": LogLevel.DEBUG;
            case "INFO": LogLevel.INFO;
            case "WARN": LogLevel.WARN;
            case "ERROR": LogLevel.ERROR;
            default: LogLevel.INFO;
        }
        
        if (cast(lvl, Int) < cast(minLevel, Int)) return;
        
        queue.add({
            time: Date.now().toString(),
            level: level,
            message: msg,
            properties: properties
        });
    }

    static function log(levelStr:String, level:LogLevel, msg:String) {
        if (cast(level, Int) < cast(minLevel, Int)) return;
        queue.add({
            time: Date.now().toString(),
            level: levelStr,
            message: msg
        });
    }

    public static function shutdown() {
        stopRequested = true;
        queue.add(null);
        Sys.sleep(0.5);
    }
}
