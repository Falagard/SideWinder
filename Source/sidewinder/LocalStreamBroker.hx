package sidewinder;

import sys.thread.Mutex;
import haxe.ds.StringMap;

/**
 * Local in-memory implementation of IStreamBroker.
 * Designed to mimic Redis Streams behavior for easy future migration.
 * 
 * This implementation is thread-safe and suitable for single-instance applications.
 * For distributed systems, use the Redis-backed implementation instead.
 */
class LocalStreamBroker implements IStreamBroker {
	// Stream storage: stream name -> array of messages
	private var streams:StringMap<Array<StreamMessage>>;
	
	// Consumer groups: stream name -> group name -> group data
	private var consumerGroups:StringMap<StringMap<ConsumerGroup>>;
	
	// Pending messages: stream:group:consumer -> array of message IDs
	private var pendingMessages:StringMap<Array<PendingMessage>>;
	
	// Message ID sequence counters
	private var messageSequence:StringMap<Int>;
	
	// Mutex for thread safety
	private var mutex:Mutex;
	
	// Configuration
	private var maxStreamLength:Int = 10000; // Default max length per stream
	private var maxPendingMessages:Int = 1000; // Max pending messages per consumer
	
	public function new() {
		streams = new StringMap<Array<StreamMessage>>();
		consumerGroups = new StringMap<StringMap<ConsumerGroup>>();
		pendingMessages = new StringMap<Array<PendingMessage>>();
		messageSequence = new StringMap<Int>();
		mutex = new Mutex();
		
		HybridLogger.info('[LocalStreamBroker] Initialized');
	}
	
	public function xadd(stream:String, data:Dynamic):String {
		mutex.acquire();
		try {
			// Initialize stream if it doesn't exist
			if (!streams.exists(stream)) {
				streams.set(stream, []);
				messageSequence.set(stream, 0);
			}
			
			// Generate message ID (timestamp-sequence)
			var timestamp = Sys.time();
			var sequence = messageSequence.get(stream);
			messageSequence.set(stream, sequence + 1);
			var messageId = '${Math.floor(timestamp * 1000)}-${sequence}';
			
			// Create message
			var message:StreamMessage = {
				id: messageId,
				data: data,
				timestamp: timestamp
			};
			
			// Add to stream
			var streamMessages = streams.get(stream);
			streamMessages.push(message);
			
			// Auto-trim if stream is too long
			if (streamMessages.length > maxStreamLength) {
				streamMessages.shift(); // Remove oldest message
				HybridLogger.debug('[LocalStreamBroker] Auto-trimmed stream: $stream');
			}
			
			HybridLogger.debug('[LocalStreamBroker] Added message to stream $stream: $messageId');
			
			return messageId;
		} finally {
			mutex.release();
		}
	}
	
	public function createGroup(stream:String, group:String, startId:String = "$"):Void {
		mutex.acquire();
		try {
			// Initialize stream if it doesn't exist
			if (!streams.exists(stream)) {
				streams.set(stream, []);
			}
			
			// Initialize consumer groups map for stream if needed
			if (!consumerGroups.exists(stream)) {
				consumerGroups.set(stream, new StringMap<ConsumerGroup>());
			}
			
			var groups = consumerGroups.get(stream);
			
			if (groups.exists(group)) {
				HybridLogger.warn('[LocalStreamBroker] Consumer group already exists: $stream:$group');
				return;
			}
			
			// Determine starting message ID
			var lastId = "0-0";
			if (startId == "$") {
				// Start from next message (current end of stream)
				var streamMessages = streams.get(stream);
				if (streamMessages.length > 0) {
					lastId = streamMessages[streamMessages.length - 1].id;
				}
			} else {
				lastId = startId;
			}
			
			// Create consumer group
			var consumerGroup:ConsumerGroup = {
				name: group,
				lastDeliveredId: lastId,
				consumers: new StringMap<Consumer>()
			};
			
			groups.set(group, consumerGroup);
			
			HybridLogger.info('[LocalStreamBroker] Created consumer group: $stream:$group (start: $lastId)');
		} finally {
			mutex.release();
		}
	}
	
	public function deleteGroup(stream:String, group:String):Void {
		mutex.acquire();
		try {
			if (!consumerGroups.exists(stream)) {
				return;
			}
			
			var groups = consumerGroups.get(stream);
			if (!groups.exists(group)) {
				return;
			}
			
			// Remove all pending messages for this group
			var consumerGroup = groups.get(group);
			for (consumerName in consumerGroup.consumers.keys()) {
				var key = '$stream:$group:$consumerName';
				pendingMessages.remove(key);
			}
			
			groups.remove(group);
			
			HybridLogger.info('[LocalStreamBroker] Deleted consumer group: $stream:$group');
		} finally {
			mutex.release();
		}
	}
	
	public function xreadgroup(group:String, consumer:String, stream:String, count:Int = 1, ?blockMs:Null<Int>):Array<StreamMessage> {
		var startTime = Sys.time();
		var blockSeconds = blockMs != null ? blockMs / 1000.0 : 0.0;
		var messages:Array<StreamMessage> = [];
		
		while (true) {
			mutex.acquire();
			try {
				// Validate stream and group exist
				if (!streams.exists(stream) || !consumerGroups.exists(stream)) {
					return messages;
				}
				
				var groups = consumerGroups.get(stream);
				if (!groups.exists(group)) {
					return messages;
				}
				
				var consumerGroup = groups.get(group);
				
				// Initialize consumer if it doesn't exist
				if (!consumerGroup.consumers.exists(consumer)) {
					consumerGroup.consumers.set(consumer, {
						name: consumer,
						pendingCount: 0,
						lastActivity: Sys.time()
					});
					HybridLogger.debug('[LocalStreamBroker] Created consumer: $stream:$group:$consumer');
				}
				
				// Update consumer activity
				var consumerData = consumerGroup.consumers.get(consumer);
				consumerData.lastActivity = Sys.time();
				
				// Get all messages after the last delivered ID
				var streamMessages = streams.get(stream);
				var lastDeliveredId = consumerGroup.lastDeliveredId;
				
				for (message in streamMessages) {
					if (compareMessageIds(message.id, lastDeliveredId) > 0) {
						messages.push(message);
						
						// Add to pending
						var key = '$stream:$group:$consumer';
						if (!pendingMessages.exists(key)) {
							pendingMessages.set(key, []);
						}
						var pending = pendingMessages.get(key);
						pending.push({
							messageId: message.id,
							consumer: consumer,
							deliveryTime: Sys.time(),
							deliveryCount: 1
						});
						
						consumerData.pendingCount++;
						consumerGroup.lastDeliveredId = message.id;
						
						if (messages.length >= count) {
							break;
						}
					}
				}
				
				// If we got messages or not blocking, return
				if (messages.length > 0 || blockMs == 0) {
					if (messages.length > 0) {
						HybridLogger.debug('[LocalStreamBroker] Read ${messages.length} messages for $stream:$group:$consumer');
					}
					return messages;
				}
			} finally {
				mutex.release();
			}
			
			// Blocking: check if timeout reached
			if (blockMs != null && blockMs > 0) {
				var elapsed = Sys.time() - startTime;
				if (elapsed >= blockSeconds) {
					return messages;
				}
				
				// Sleep briefly before checking again
				Sys.sleep(0.05); // 50ms
			} else {
				// No blocking, return empty
				return messages;
			}
		}
		
		return messages;
	}
	
	public function xack(stream:String, group:String, messageIds:Array<String>):Int {
		mutex.acquire();
		try {
			var ackCount = 0;
			
			// Find and remove pending messages
			for (key in pendingMessages.keys()) {
				if (!key.startsWith('$stream:$group:')) {
					continue;
				}
				
				var pending = pendingMessages.get(key);
				var remaining:Array<PendingMessage> = [];
				
				for (p in pending) {
					if (messageIds.indexOf(p.messageId) == -1) {
						remaining.push(p);
					} else {
						ackCount++;
					}
				}
				
				if (remaining.length == 0) {
					pendingMessages.remove(key);
				} else {
					pendingMessages.set(key, remaining);
				}
				
				// Update consumer pending count
				if (consumerGroups.exists(stream)) {
					var groups = consumerGroups.get(stream);
					if (groups.exists(group)) {
						var consumerGroup = groups.get(group);
						var consumerName = key.substr(key.lastIndexOf(':') + 1);
						if (consumerGroup.consumers.exists(consumerName)) {
							var consumer = consumerGroup.consumers.get(consumerName);
							consumer.pendingCount = remaining.length;
						}
					}
				}
			}
			
			if (ackCount > 0) {
				HybridLogger.debug('[LocalStreamBroker] Acknowledged $ackCount messages for $stream:$group');
			}
			
			return ackCount;
		} finally {
			mutex.release();
		}
	}
	
	public function xpending(stream:String, group:String, ?consumer:String):Array<StreamMessage> {
		mutex.acquire();
		try {
			var result:Array<StreamMessage> = [];
			
			if (!streams.exists(stream)) {
				return result;
			}
			
			var streamMessages = streams.get(stream);
			var pendingIds:Array<String> = [];
			
			// Collect pending message IDs
			for (key in pendingMessages.keys()) {
				if (consumer != null) {
					if (key != '$stream:$group:$consumer') {
						continue;
					}
				} else {
					if (!key.startsWith('$stream:$group:')) {
						continue;
					}
				}
				
				var pending = pendingMessages.get(key);
				for (p in pending) {
					pendingIds.push(p.messageId);
				}
			}
			
			// Find the actual messages
			for (message in streamMessages) {
				if (pendingIds.indexOf(message.id) != -1) {
					result.push(message);
				}
			}
			
			return result;
		} finally {
			mutex.release();
		}
	}
	
	public function xautoclaim(stream:String, group:String, consumer:String, minIdleMs:Int, count:Int = 1):Array<StreamMessage> {
		mutex.acquire();
		try {
			var claimed:Array<StreamMessage> = [];
			var minIdleSeconds = minIdleMs / 1000.0;
			var now = Sys.time();
			
			if (!streams.exists(stream) || !consumerGroups.exists(stream)) {
				return claimed;
			}
			
			var groups = consumerGroups.get(stream);
			if (!groups.exists(group)) {
				return claimed;
			}
			
			var consumerGroup = groups.get(group);
			var streamMessages = streams.get(stream);
			
			// Find stale pending messages from other consumers
			for (key in pendingMessages.keys()) {
				if (!key.startsWith('$stream:$group:') || key == '$stream:$group:$consumer') {
					continue;
				}
				
				var oldConsumer = key.substr(key.lastIndexOf(':') + 1);
				var pending = pendingMessages.get(key);
				var remaining:Array<PendingMessage> = [];
				
				for (p in pending) {
					var idleTime = now - p.deliveryTime;
					if (idleTime >= minIdleSeconds && claimed.length < count) {
						// Claim this message
						var message = findMessageById(streamMessages, p.messageId);
						if (message != null) {
							claimed.push(message);
							
							// Add to new consumer's pending
							var newKey = '$stream:$group:$consumer';
							if (!pendingMessages.exists(newKey)) {
								pendingMessages.set(newKey, []);
							}
							var newPending = pendingMessages.get(newKey);
							newPending.push({
								messageId: p.messageId,
								consumer: consumer,
								deliveryTime: now,
								deliveryCount: p.deliveryCount + 1
							});
						}
					} else {
						remaining.push(p);
					}
				}
				
				// Update old consumer's pending
				if (remaining.length == 0) {
					pendingMessages.remove(key);
				} else {
					pendingMessages.set(key, remaining);
				}
				
				// Update consumer pending counts
				if (consumerGroup.consumers.exists(oldConsumer)) {
					consumerGroup.consumers.get(oldConsumer).pendingCount = remaining.length;
				}
				if (consumerGroup.consumers.exists(consumer)) {
					var newConsumer = consumerGroup.consumers.get(consumer);
					var newKey = '$stream:$group:$consumer';
					if (pendingMessages.exists(newKey)) {
						newConsumer.pendingCount = pendingMessages.get(newKey).length;
					}
				}
			}
			
			if (claimed.length > 0) {
				HybridLogger.debug('[LocalStreamBroker] Auto-claimed ${claimed.length} messages for $stream:$group:$consumer');
			}
			
			return claimed;
		} finally {
			mutex.release();
		}
	}
	
	public function xlen(stream:String):Int {
		mutex.acquire();
		try {
			if (!streams.exists(stream)) {
				return 0;
			}
			return streams.get(stream).length;
		} finally {
			mutex.release();
		}
	}
	
	public function getGroupInfo(stream:String):Array<ConsumerGroupInfo> {
		mutex.acquire();
		try {
			var result:Array<ConsumerGroupInfo> = [];
			
			if (!consumerGroups.exists(stream)) {
				return result;
			}
			
			var groups = consumerGroups.get(stream);
			for (groupName in groups.keys()) {
				var group = groups.get(groupName);
				
				var consumers:Array<ConsumerInfo> = [];
				var totalPending = 0;
				
				for (consumerName in group.consumers.keys()) {
					var consumer = group.consumers.get(consumerName);
					consumers.push({
						name: consumer.name,
						pending: consumer.pendingCount,
						lastActivity: consumer.lastActivity
					});
					totalPending += consumer.pendingCount;
				}
				
				result.push({
					name: group.name,
					consumers: consumers,
					lastDeliveredId: group.lastDeliveredId,
					totalPending: totalPending
				});
			}
			
			return result;
		} finally {
			mutex.release();
		}
	}
	
	public function deleteConsumer(stream:String, group:String, consumer:String):Int {
		mutex.acquire();
		try {
			if (!consumerGroups.exists(stream)) {
				return 0;
			}
			
			var groups = consumerGroups.get(stream);
			if (!groups.exists(group)) {
				return 0;
			}
			
			var consumerGroup = groups.get(group);
			if (!consumerGroup.consumers.exists(consumer)) {
				return 0;
			}
			
			var pendingCount = consumerGroup.consumers.get(consumer).pendingCount;
			
			// Remove consumer
			consumerGroup.consumers.remove(consumer);
			
			// Remove pending messages
			var key = '$stream:$group:$consumer';
			pendingMessages.remove(key);
			
			HybridLogger.info('[LocalStreamBroker] Deleted consumer: $stream:$group:$consumer (had $pendingCount pending)');
			
			return pendingCount;
		} finally {
			mutex.release();
		}
	}
	
	public function xtrim(stream:String, maxLen:Int):Int {
		mutex.acquire();
		try {
			if (!streams.exists(stream)) {
				return 0;
			}
			
			var streamMessages = streams.get(stream);
			var originalLength = streamMessages.length;
			
			if (originalLength <= maxLen) {
				return 0;
			}
			
			// Remove oldest messages
			var toRemove = originalLength - maxLen;
			streamMessages.splice(0, toRemove);
			
			HybridLogger.info('[LocalStreamBroker] Trimmed stream $stream: removed $toRemove messages');
			
			return toRemove;
		} finally {
			mutex.release();
		}
	}
	
	// Helper methods
	
	/**
	 * Compare two message IDs.
	 * Returns: -1 if id1 < id2, 0 if equal, 1 if id1 > id2
	 */
	private function compareMessageIds(id1:String, id2:String):Int {
		var parts1 = id1.split('-');
		var parts2 = id2.split('-');
		
		var timestamp1 = Std.parseInt(parts1[0]);
		var timestamp2 = Std.parseInt(parts2[0]);
		
		if (timestamp1 < timestamp2) return -1;
		if (timestamp1 > timestamp2) return 1;
		
		var seq1 = Std.parseInt(parts1[1]);
		var seq2 = Std.parseInt(parts2[1]);
		
		if (seq1 < seq2) return -1;
		if (seq1 > seq2) return 1;
		
		return 0;
	}
	
	private function findMessageById(messages:Array<StreamMessage>, id:String):Null<StreamMessage> {
		for (message in messages) {
			if (message.id == id) {
				return message;
			}
		}
		return null;
	}
}

// Internal data structures

private typedef ConsumerGroup = {
	var name:String;
	var lastDeliveredId:String;
	var consumers:StringMap<Consumer>;
}

private typedef Consumer = {
	var name:String;
	var pendingCount:Int;
	var lastActivity:Float;
}

private typedef PendingMessage = {
	var messageId:String;
	var consumer:String;
	var deliveryTime:Float;
	var deliveryCount:Int;
}
