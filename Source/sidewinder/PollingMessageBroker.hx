package sidewinder;

import sys.thread.Mutex;
import sys.thread.Thread;
import haxe.ds.StringMap;

/**
 * Polling-based implementation of IMessageBroker.
 * Uses in-memory message queues and long-polling for message delivery.
 */
class PollingMessageBroker implements IMessageBroker {
	private static final MAX_QUEUE_SIZE = 100;
	private static final CLEANUP_INTERVAL = 300.0; // 5 minutes
	private static final POLL_CHECK_INTERVAL = 0.1; // 100ms

	private var clientQueues:StringMap<Array<String>>;
	private var clientLastActivity:StringMap<Float>;
	private var mutex:Mutex;
	private var cleanupThread:Thread;
	private var running:Bool;

	public function new() {
		clientQueues = new StringMap<Array<String>>();
		clientLastActivity = new StringMap<Float>();
		mutex = new Mutex();
		running = true;

		// Start cleanup thread to remove inactive clients
		cleanupThread = Thread.create(() -> {
			while (running) {
				Sys.sleep(CLEANUP_INTERVAL);
				cleanupInactiveClients();
			}
		});

		HybridLogger.info('[PollingMessageBroker] Initialized');
	}

	public function subscribe(clientId:String):Void {
		mutex.acquire();
		if (!clientQueues.exists(clientId)) {
			clientQueues.set(clientId, []);
			clientLastActivity.set(clientId, Sys.time());
			HybridLogger.debug('[PollingMessageBroker] Client subscribed: $clientId');
		} else {
			// Update activity timestamp
			clientLastActivity.set(clientId, Sys.time());
		}
		mutex.release();
	}

	public function unsubscribe(clientId:String):Void {
		mutex.acquire();
		if (clientQueues.exists(clientId)) {
			clientQueues.remove(clientId);
			clientLastActivity.remove(clientId);
			HybridLogger.debug('[PollingMessageBroker] Client unsubscribed: $clientId');
		}
		mutex.release();
	}

	public function sendToClient(clientId:String, message:String):Void {
		mutex.acquire();
		if (clientQueues.exists(clientId)) {
			var queue = clientQueues.get(clientId);
			if (queue.length < MAX_QUEUE_SIZE) {
				queue.push(message);
				HybridLogger.debug('[PollingMessageBroker] Message queued for $clientId: ${message.substr(0, 50)}...');
			} else {
				HybridLogger.warn('[PollingMessageBroker] Queue full for client $clientId, dropping message');
			}
		} else {
			HybridLogger.warn('[PollingMessageBroker] Client not found: $clientId');
		}
		mutex.release();
	}

	public function broadcast(message:String):Void {
		mutex.acquire();
		var count = 0;
		for (clientId in clientQueues.keys()) {
			var queue = clientQueues.get(clientId);
			if (queue.length < MAX_QUEUE_SIZE) {
				queue.push(message);
				count++;
			}
		}
		HybridLogger.debug('[PollingMessageBroker] Broadcast to $count clients: ${message.substr(0, 50)}...');
		mutex.release();
	}

	public function getMessages(clientId:String, timeout:Float):Array<String> {
		var startTime = Sys.time();
		var messages:Array<String> = [];

		// Update activity timestamp
		mutex.acquire();
		if (clientLastActivity.exists(clientId)) {
			clientLastActivity.set(clientId, Sys.time());
		}
		mutex.release();

		// Long-polling: wait for messages or timeout
		while (Sys.time() - startTime < timeout) {
			mutex.acquire();
			if (clientQueues.exists(clientId)) {
				var queue = clientQueues.get(clientId);
				if (queue.length > 0) {
					// Return all pending messages
					messages = queue.copy();
					// Clear the queue
					while (queue.length > 0) queue.pop();
					HybridLogger.debug('[PollingMessageBroker] Returning ${messages.length} messages to $clientId');
					mutex.release();
					return messages;
				}
			} else {
				// Client not subscribed
				HybridLogger.warn('[PollingMessageBroker] Client not subscribed during poll: $clientId');
				mutex.release();
				return [];
			}
			mutex.release();

			// Sleep briefly before checking again
			Sys.sleep(POLL_CHECK_INTERVAL);
		}

		// Timeout reached, return empty array
		HybridLogger.debug('[PollingMessageBroker] Poll timeout for $clientId');
		return messages;
	}

	public function isSubscribed(clientId:String):Bool {
		mutex.acquire();
		var result = clientQueues.exists(clientId);
		mutex.release();
		return result;
	}

	public function getClientCount():Int {
		mutex.acquire();
		var count = 0;
		for (_ in clientQueues.keys()) count++;
		mutex.release();
		return count;
	}

	private function cleanupInactiveClients():Void {
		mutex.acquire();
		var now = Sys.time();
		var toRemove:Array<String> = [];

		for (clientId in clientLastActivity.keys()) {
			var lastActivity = clientLastActivity.get(clientId);
			if (now - lastActivity > CLEANUP_INTERVAL) {
				toRemove.push(clientId);
			}
		}

		for (clientId in toRemove) {
			clientQueues.remove(clientId);
			clientLastActivity.remove(clientId);
			HybridLogger.info('[PollingMessageBroker] Cleaned up inactive client: $clientId');
		}

		if (toRemove.length > 0) {
			HybridLogger.info('[PollingMessageBroker] Cleaned up ${toRemove.length} inactive clients');
		}
		mutex.release();
	}

	public function shutdown():Void {
		running = false;
		HybridLogger.info('[PollingMessageBroker] Shutting down');
	}
}
