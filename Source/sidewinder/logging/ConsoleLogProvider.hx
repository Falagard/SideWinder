package sidewinder.logging;

import sidewinder.interfaces.ILogProvider;

/**
 * Log provider that writes log entries to the system console.
 */
class ConsoleLogProvider implements ILogProvider {
	public function new() {}

	public function log(entry:LogEntry):Void {
		var levelStr = entry.level;
		var msg = entry.message;
		var time = entry.time;
		
		Sys.println('[$time] [$levelStr] $msg');
		
		if (entry.properties != null) {
			for (k in entry.properties.keys()) {
				Sys.println('  $k: ${entry.properties.get(k)}');
			}
		}
	}

	public function flush():Void {
		// No buffering for console
	}

	public function shutdown():Void {
		// Nothing to clean up
	}
}
