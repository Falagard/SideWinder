package sidewinder;

import sys.io.File;
import sys.FileSystem;
import sidewinder.ILogProvider;

/**
 * File-based log provider with daily rotation.
 */
class FileLogProvider implements ILogProvider {
	private var logDir:String;
	private var currentDate:String;
	private var logFile:sys.io.FileOutput;

	public function new(logDir:String = "logs") {
		this.logDir = logDir;
		if (!FileSystem.exists(logDir)) {
			FileSystem.createDirectory(logDir);
		}
		openLogFile();
	}

	public function log(entry:LogEntry):Void {
		rotateIfNeeded();
		try {
			var line = '[${entry.time}] ${entry.level.toUpperCase()} ${entry.message}\n';
			logFile.writeString(line);
		} catch (e:Dynamic) {
			trace('FileLogProvider: Failed to write log: $e');
		}
	}

	public function flush():Void {
		try {
			logFile.flush();
		} catch (e:Dynamic) {
			trace('FileLogProvider: Failed to flush: $e');
		}
	}

	public function shutdown():Void {
		try {
			logFile.flush();
			logFile.close();
		} catch (e:Dynamic) {
			trace('FileLogProvider: Failed to shutdown: $e');
		}
	}

	private function openLogFile():Void {
		currentDate = Date.now().toString().substr(0, 10);
		var fileName = '$logDir/app-$currentDate.log';
		logFile = File.append(fileName);
	}

	private function rotateIfNeeded():Void {
		var today = Date.now().toString().substr(0, 10);
		if (today != currentDate) {
			try {
				logFile.close();
			} catch (e:Dynamic) {}
			openLogFile();
		}
	}
}
