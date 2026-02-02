package sidewinder;

import haxe.Json;
import sys.thread.Thread;
import sys.thread.Lock;

typedef EmailTemplateConsumerOptions = {
	?streamName:String,
	?groupName:String,
	?consumerName:String,
	?readCount:Int,
	?blockMs:Int,
	?ackOnError:Bool
}

class EmailTemplateStreamConsumer {
	public static inline var DEFAULT_STREAM = "email-templates";
	public static inline var DEFAULT_GROUP = "email-workers";
	public static inline var DEFAULT_CONSUMER = "worker-1";

	public static function start(
		broker:IStreamBroker,
		notificationService:INotificationService,
		templateEngine:EmailTemplateEngine,
		?options:EmailTemplateConsumerOptions
	):Void {
		var streamName = options != null && options.streamName != null ? options.streamName : DEFAULT_STREAM;
		var groupName = options != null && options.groupName != null ? options.groupName : DEFAULT_GROUP;
		var consumerName = options != null && options.consumerName != null ? options.consumerName : DEFAULT_CONSUMER;
		var readCount = options != null && options.readCount != null ? options.readCount : 5;
		var blockMs = options != null && options.blockMs != null ? options.blockMs : 5000;
		var ackOnError = options != null && options.ackOnError != null ? options.ackOnError : true;

		broker.createGroup(streamName, groupName, "$");

		Thread.create(() -> {
			HybridLogger.info('[EmailTemplateConsumer] Listening on stream "$streamName" group "$groupName" as "$consumerName"');
			while (true) {
				var messages = broker.xreadgroup(groupName, consumerName, streamName, readCount, blockMs);
				if (messages.length == 0) {
					continue;
				}

				for (msg in messages) {
					var shouldAck = false;
					try {
						processMessage(notificationService, templateEngine, msg.data);
						shouldAck = true;
					} catch (e:Dynamic) {
						HybridLogger.error('[EmailTemplateConsumer] Failed processing message ${msg.id}: $e');
						shouldAck = ackOnError;
					}

					if (shouldAck) {
						broker.xack(streamName, groupName, [msg.id]);
					}
				}
			}
		});
	}

	private static function processMessage(
		notificationService:INotificationService,
		templateEngine:EmailTemplateEngine,
		payload:Dynamic
	):Void {
		var message:Dynamic = payload;
		if (Std.isOfType(message, String)) {
			message = Json.parse(cast message);
		}

		var to:String = Reflect.field(message, "to");
		var subject:String = Reflect.field(message, "subject");
		var templateName:String = Reflect.field(message, "templateName");
		var dataPayload:Dynamic = Reflect.field(message, "data");

		if (to == null || subject == null || templateName == null) {
			throw 'Missing required fields: to, subject, templateName';
		}

		var templateData = EmailTemplateEngine.coerceData(dataPayload);
		var body = templateEngine.render(templateName, templateData);

		var lock = new Lock();
		var sendError:Dynamic = null;
		notificationService.sendEmail(to, subject, body, false, function(err:Dynamic) {
			sendError = err;
			lock.release();
		});
		lock.wait();

		if (sendError != null) {
			throw sendError;
		}
	}
}
