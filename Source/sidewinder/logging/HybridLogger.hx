package sidewinder.logging;
#if (html5 && !sys)
#error "HybridLogger is not available on HTML5. Use a client-side logger instead."
#end

import sidewinder.interfaces.ILogProvider.LogEntry;

import sidewinder.interfaces.ILogProvider;


import sys.thread.Thread;
#if !hl
import sys.thread.Deque;
#end


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
	// HL GC SIGNAL 11 fix: sys.thread.Deque uses ArrayDyn internally; on HashLink
	// the GC fires during ArrayDyn.alloc when the logger thread calls pop() concurrently
	// with a request thread calling add(), causing SIGSEGV.  Replace with List<T> guarded
	// by a Mutex (no ArrayDyn) and a Lock for worker wake-up (blocks in native sem_wait
	// with zero GC safepoints, unlike Deque.pop(true) which spins through safepoints).
	#if hl
	static var _list:List<LogEntry> = new List<LogEntry>();
	static var _mutex = new sys.thread.Mutex();
	static var _signal = new sys.thread.Lock();
	#else
	static var queue = new Deque<LogEntry>();
	#end
	static var workerStarted = false;
	static var stopRequested = false;
	static var providers:Array<ILogProvider> = [];
	static var minLevel:LogLevel = LogLevel.DEBUG;

	/**
	 * Initialize the logger with optional minimum log level.
	 * @param minLvl Minimum log level to process (default: INFO)
	 */
	public static function init(?minLvl:LogLevel = INFO) {
		if (workerStarted)
			return;
		workerStarted = true;
		minLevel = minLvl;

		Thread.create(() -> {
			while (!stopRequested) {
				#if hl
				_signal.wait(1.0);
				_mutex.acquire();
				var entry:Null<LogEntry> = _list.pop();
				_mutex.release();
				#else
				var entry = queue.pop(true);
				#end
				if (entry == null)
					continue;

				// Send to all registered providers
				for (provider in providers) {
					try {
						provider.log(entry);
					} catch (e:Dynamic) {
						trace('HybridLogger: Provider error: $e');
					}
				}
			}

			// Drain remaining entries before shutdown
			#if hl
			_mutex.acquire();
			var remaining = _list.length;
			_mutex.release();
			while (remaining > 0) {
				_mutex.acquire();
				var entry:Null<LogEntry> = _list.pop();
				_mutex.release();
				if (entry != null) {
					for (provider in providers) {
						try { provider.log(entry); } catch (e:Dynamic) {}
					}
				}
				_mutex.acquire();
				remaining = _list.length;
				_mutex.release();
			}
			#end

			// Shutdown all providers
			for (provider in providers) {
				try {
					provider.shutdown();
				} catch (e:Dynamic) {
					trace('HybridLogger: Provider shutdown error: $e');
				}
			}
			exitLock.release();
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

	public static inline function debug(msg:String)
		log("DEBUG", LogLevel.DEBUG, msg);

	public static inline function info(msg:String)
		log("INFO", LogLevel.INFO, msg);

	public static inline function warn(msg:String)
		log("WARN", LogLevel.WARN, msg);

	public static inline function error(msg:String)
		log("ERROR", LogLevel.ERROR, msg);

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

		if (cast(lvl, Int) < cast(minLevel, Int))
			return;

		#if hl
		_mutex.acquire();
		_list.push({time: Date.now().toString(), level: level, message: msg, properties: properties});
		_mutex.release();
		_signal.release();
		#else
		queue.add({
			time: Date.now().toString(),
			level: level,
			message: msg,
			properties: properties
		});
		#end
	}

	static function log(levelStr:String, level:LogLevel, msg:String) {
		if (cast(level, Int) < cast(minLevel, Int))
			return;
		#if hl
		_mutex.acquire();
		_list.push({time: Date.now().toString(), level: levelStr, message: msg});
		_mutex.release();
		_signal.release();
		#else
		queue.add({
			time: Date.now().toString(),
			level: levelStr,
			message: msg
		});
		#end
	}

	static var exitLock = new sys.thread.Lock();
	static var shutdownFinished = false;

	public static function shutdown() {
		if (shutdownFinished) return;
		stopRequested = true;
		#if hl
		_signal.release();  // wake the worker so it can exit the while loop
		#else
		queue.add(null);
		#end

		#if !html5
		// Wait for the worker thread to signal it's done
		if (workerStarted) {
			exitLock.wait(2.0); // Wait up to 2 seconds
		}
		#end
		shutdownFinished = true;
	}
}
