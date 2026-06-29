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
		
		#if hl hl.Gc.enable(false); #end
		var line = '[$time] [$levelStr] $msg';
		#if hl hl.Gc.enable(true); #end
		Sys.println(line);

		if (entry.properties != null) {
			for (k in entry.properties.keys()) {
				#if hl hl.Gc.enable(false); #end
				var propLine = '  $k: ${entry.properties.get(k)}';
				#if hl hl.Gc.enable(true); #end
				Sys.println(propLine);
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
