package sidewinder.interfaces;

import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;


typedef LogEntry = {
    time:String,
    level:String,
    message:String,
    ?properties:Map<String, Dynamic>
}

/**
 * Interface for log providers. Implementations can send logs to different destinations.
 */
interface ILogProvider {
    /**
     * Log a message with the given level and optional properties.
     * @param entry The log entry to write
     */
    function log(entry:LogEntry):Void;
    
    /**
     * Flush any buffered log entries immediately.
     */
    function flush():Void;
    
    /**
     * Shutdown the log provider and clean up resources.
     */
    function shutdown():Void;
}



