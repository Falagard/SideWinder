package sidewinder.core;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;

import sidewinder.logging.HybridLogger;
import sidewinder.interfaces.IStreamBroker;
import sidewinder.interfaces.IJobStore;
import sidewinder.interfaces.IMessageBroker;
import sidewinder.data.JobStatus;


import haxe.Json;
import sys.thread.Thread;



/**
 * Basic job payload structure.
 */
typedef JobPayload = {
	var id:String;
	var type:String;
	var clientId:String;
	var data:Dynamic;
}

/**
 * A background consumer that processes jobs from the "jobs" stream.
 */
class GenericJobWorker {
	public static inline var DEFAULT_STREAM = "jobs";
	public static inline var DEFAULT_GROUP = "job-workers";

	public static function start(
		broker:IStreamBroker,
		jobStore:IJobStore,
		messageBroker:IMessageBroker
	):Void {
		
		broker.createGroup(DEFAULT_STREAM, DEFAULT_GROUP, "$");

		Thread.create(() -> {
			HybridLogger.info('[GenericJobWorker] Started listening on "$DEFAULT_STREAM"');
			
			while (true) {
				try {
					var messages = broker.xreadgroup(DEFAULT_GROUP, "worker-1", DEFAULT_STREAM, 1, 5000);
					if (messages.length == 0) continue;

					HybridLogger.debug('[GenericJobWorker] Received ${messages.length} messages from stream');

					for (msg in messages) {
						var payload:JobPayload = msg.data;
						HybridLogger.info('[GenericJobWorker] Processing job ${payload.id} of type ${payload.type}');
						
						// Update status to Processing
						jobStore.updateStatus(payload.id, JobStatus.Processing);
						
						try {
							// Execute the "work"
							var resultData = processJob(payload);
							
							// Update status to Completed
							jobStore.updateStatus(payload.id, JobStatus.Completed, resultData);
							
							// Notify via MessageBroker
							messageBroker.sendToClient(payload.clientId, Json.stringify({
								event: "job_complete",
								jobId: payload.id,
								result: resultData
							}));
							
						} catch (e:Dynamic) {
							HybridLogger.error('[GenericJobWorker] Job ${payload.id} failed: $e');
							jobStore.updateStatus(payload.id, JobStatus.Failed(Std.string(e)));
							
							messageBroker.sendToClient(payload.clientId, Json.stringify({
								event: "job_failed",
								jobId: payload.id,
								error: Std.string(e)
							}));
						}

						// Acknowledge the message
						broker.xack(DEFAULT_STREAM, DEFAULT_GROUP, [msg.id]);
					}
				} catch (e:Dynamic) {
					HybridLogger.error('[GenericJobWorker] Loop error: $e');
					#if !html5
					Sys.sleep(1);
					#end
				}
			}
		});
	}

	private static function processJob(payload:JobPayload):Dynamic {
		// This is where specific job logic would go.
		// For a demo, let's handle a "delay" job type.
		
		switch (payload.type) {
			case "delay":
				var seconds = payload.data != null && payload.data.seconds != null ? payload.data.seconds : 2;
				HybridLogger.info('[GenericJobWorker] Simulating work for $seconds seconds...');
				#if !html5
				Sys.sleep(seconds);
				#end
				return { message: "Work completed after " + seconds + "s delay", time: Date.now().toString() };
			
			case "echo":
				return { echoed: payload.data };

			default:
				throw "Unknown job type: " + payload.type;
		}
	}
}




