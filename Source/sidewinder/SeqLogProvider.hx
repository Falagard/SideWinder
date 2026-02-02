package sidewinder;

import haxe.Json;
import haxe.Http;
import haxe.io.Bytes;

/**
 * Seq log provider - sends structured logs to a Seq server.
 * 
 * Seq is a centralized logging service that accepts structured logs via HTTP.
 * See: https://datalust.co/seq
 * 
 * Usage:
 * ```haxe
 * var seqProvider = new SeqLogProvider("http://localhost:5341", "your-api-key");
 * HybridLogger.addProvider(seqProvider);
 * ```
 */
class SeqLogProvider implements ILogProvider {
    private var seqUrl:String;
    private var apiKey:String;
    private var batch:Array<Dynamic> = [];
    private var batchSize:Int;
    private var minLevel:String;
    
    /**
     * Create a new Seq log provider.
     * @param seqUrl The base URL of your Seq server (e.g., "http://localhost:5341")
     * @param apiKey Optional API key for authentication
     * @param batchSize Number of log entries to batch before sending (default: 10)
     * @param minLevel Minimum log level to send to Seq (default: "DEBUG")
     */
    public function new(seqUrl:String, ?apiKey:String, batchSize:Int = 10, minLevel:String = "DEBUG") {
        this.seqUrl = seqUrl.charAt(seqUrl.length - 1) == "/" ? seqUrl.substr(0, seqUrl.length - 1) : seqUrl;
        this.apiKey = apiKey;
        this.batchSize = batchSize;
        this.minLevel = minLevel;
    }
    
    public function log(entry:LogEntry):Void {
        // Check if log level meets minimum threshold
        if (!shouldLog(entry.level)) {
            return;
        }
        
        // Convert log entry to Seq CLEF format
        var seqEvent = {
            "@t": entry.time,
            "@l": mapLogLevel(entry.level),
            "@mt": entry.message,
            "@i": generateEventId()
        };
        
        // Add custom properties if provided
        if (entry.properties != null) {
            for (key in entry.properties.keys()) {
                Reflect.setField(seqEvent, key, entry.properties.get(key));
            }
        }
        
        batch.push(seqEvent);
        
        if (batch.length >= batchSize) {
            flush();
        }
    }
    
    public function flush():Void {
        if (batch.length == 0) return;
        
        var eventsToSend = batch.copy();
        batch = [];
        
        try {
            sendToSeq(eventsToSend);
        } catch (e:Dynamic) {
            trace('SeqLogProvider: Failed to send logs: $e');
            // In case of failure, we could optionally re-queue or write to file
        }
    }
    
    public function shutdown():Void {
        flush();
    }
    
    private function sendToSeq(events:Array<Dynamic>):Void {
        var url = '$seqUrl/api/events/raw?clef';
        
        // Convert events to CLEF format (newline-delimited JSON)
        var clefLines = [];
        for (event in events) {
            clefLines.push(Json.stringify(event));
        }
        var body = clefLines.join("\n");
        
        var http = new Http(url);
        http.setHeader("Content-Type", "application/vnd.serilog.clef");
        
        if (apiKey != null && apiKey.length > 0) {
            http.setHeader("X-Seq-ApiKey", apiKey);
        }
        
        http.onError = function(error) {
            trace('SeqLogProvider: HTTP error: $error');
        };
        
        http.onStatus = function(status) {
            if (status < 200 || status >= 300) {
                trace('SeqLogProvider: Server returned status $status');
            }
        };
        
        http.setPostData(body);
        http.request(true); // POST
    }
    
    private function mapLogLevel(level:String):String {
        return switch (level.toUpperCase()) {
            case "DEBUG": "Debug";
            case "INFO": "Information";
            case "WARN": "Warning";
            case "ERROR": "Error";
            default: "Information";
        }
    }
    
    private function shouldLog(level:String):Bool {
        var levelMap = ["DEBUG" => 0, "INFO" => 1, "WARN" => 2, "ERROR" => 3];
        var currentLevel = levelMap.get(level.toUpperCase());
        var minLevelValue = levelMap.get(minLevel.toUpperCase());
        
        if (currentLevel == null) currentLevel = 1;
        if (minLevelValue == null) minLevelValue = 0;
        
        return currentLevel >= minLevelValue;
    }
    
    private static var eventIdCounter:Int = 0;
    private function generateEventId():String {
        return Std.string(eventIdCounter++);
    }
}
