package sidewinder.data;

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


/**
 * Represents the current state of an asynchronous job.
 */
enum JobStatus {
	Pending;
	Processing;
	Completed;
	Failed(error:String);
}



