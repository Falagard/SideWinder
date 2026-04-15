package sidewinder.messaging;
#if (html5 && !sys)
#error "LocalStreamBroker is not available on HTML5."
#end

import sys.thread.Mutex;
import haxe.ds.StringMap;
import sidewinder.interfaces.IStreamBroker;
import sidewinder.interfaces.IStreamBroker.StreamMessage;
import sidewinder.interfaces.IStreamBroker.ConsumerInfo;
import sidewinder.interfaces.IStreamBroker.ConsumerGroupInfo;
import sidewinder.logging.HybridLogger;

using StringTools;

/**
 * Local in-memory implementation of IStreamBroker.
 * Designed to mimic Redis Streams behavior for easy future migration.
 * 
 * This implementation is thread-safe and suitable for single-instance applications.
 * For distributed systems, use the Redis-backed implementation instead.
 */
class LocalStreamBroker implements IStreamBroker {
	// Stream storage: stream name -> array of messages
	private static var _streams:StringMap<Array<StreamMessage>>;
	private static var _consumerGroups:StringMap<StringMap<ConsumerGroup>>;
	private static var _pendingMessages:StringMap<Array<PendingMessage>>;
	private static var _messageSequence:StringMap<Int>;
	private static var _mutex:Mutex = new Mutex();
	private static var _globalInstanceCount:Int = 0;

	private var instanceId:Int;
	private var maxStreamLength:Int = 10000;
	private var maxPendingMessages:Int = 1000;

	public function new() {
		initShared();
		_mutex.acquire();
		this.instanceId = ++_globalInstanceCount;
		_mutex.release();
	}

	private static function initShared():Void {
		_mutex.acquire();
		var tid = Std.string(sys.thread.Thread.current());
		if (_streams == null) {
			_streams = new StringMap<Array<StreamMessage>>();
			_consumerGroups = new StringMap<StringMap<ConsumerGroup>>();
			_pendingMessages = new StringMap<Array<PendingMessage>>();
			_messageSequence = new StringMap<Int>();
		}
		_mutex.release();
	}

	public function getConstructorArgs():Array<String> {
		return [];
	}

	public function xadd(stream:String, data:Dynamic):String {
		_mutex.acquire();
		try {
			// Initialize stream if it doesn't exist
			if (!_streams.exists(stream)) {
				_streams.set(stream, []);
				_messageSequence.set(stream, 0);
			}

			// Generate message ID (timestamp-sequence)
			// Use Date.now().getTime() to get milliseconds as Float, then convert to string
			// This avoids integer overflow that occurs with Math.floor() on large timestamps
			var timestampMs = Date.now().getTime();
			var sequence = _messageSequence.get(stream);
			_messageSequence.set(stream, sequence + 1);
			// Use fixed-point string representation for large timestamps
			var messageId = '${Math.ffloor(timestampMs)}-${sequence}';

			// Create message
			var message:StreamMessage = {
				id: messageId,
				data: data,
				timestamp: timestampMs / 1000
			};

			// Add to stream
			var streamMessages = _streams.get(stream);
			streamMessages.push(message);

			_mutex.release();
			return messageId;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function createGroup(stream:String, group:String, startId:String = "$"):Void {
		_mutex.acquire();
		try {
			// Initialize stream if it doesn't exist
			if (!_streams.exists(stream)) {
				_streams.set(stream, []);
			}

			// Initialize consumer groups map for stream if needed
			if (!_consumerGroups.exists(stream)) {
				_consumerGroups.set(stream, new StringMap<ConsumerGroup>());
			}

			var groups = _consumerGroups.get(stream);

			if (groups.exists(group)) {
				HybridLogger.warn('[LocalStreamBroker] Consumer group already exists: $stream:$group');
				_mutex.release();
				return;
			}

			// Determine starting message ID
			var lastId = "0-0";
			if (startId == "$") {
				// Start from next message (current end of stream)
				var streamMessages = _streams.get(stream);
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
			_mutex.release();
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function deleteGroup(stream:String, group:String):Void {
		_mutex.acquire();
		try {
			if (!_consumerGroups.exists(stream)) {
				_mutex.release();
				return;
			}

			var groups = _consumerGroups.get(stream);
			if (!groups.exists(group)) {
				_mutex.release();
				return;
			}

			// Remove all pending messages for this group
			var consumerGroup = groups.get(group);
			for (consumerName in consumerGroup.consumers.keys()) {
				var key = '$stream:$group:$consumerName';
				_pendingMessages.remove(key);
			}

			groups.remove(group);

			HybridLogger.info('[LocalStreamBroker] Deleted consumer group: $stream:$group');
			_mutex.release();
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function xreadgroup(group:String, consumer:String, stream:String, count:Int = 1, ?blockMs:Null<Int>):Array<StreamMessage> {
		var startTime = Sys.time();
		var blockSeconds = blockMs != null ? blockMs / 1000.0 : 0.0;
		var messages:Array<StreamMessage> = [];

		while (true) {
			_mutex.acquire();
			try {
				// Validate stream and group exist
				if (!_streams.exists(stream) || !_consumerGroups.exists(stream)) {
					// Silent return, but we want to know it's not a crash
					_mutex.release();
					return messages;
				}

				var groups = _consumerGroups.get(stream);
				if (!groups.exists(group)) {
					_mutex.release();
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
				var streamMessages = _streams.get(stream);
				var lastDeliveredId = consumerGroup.lastDeliveredId;

				for (message in streamMessages) {
					if (this.compareMessageIds(message.id, lastDeliveredId) > 0) {
						messages.push(message);

						// Add to pending
						var key = '$stream:$group:$consumer';
						if (!_pendingMessages.exists(key)) {
							_pendingMessages.set(key, []);
						}
						var pending = _pendingMessages.get(key);
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
					_mutex.release();
					return messages;
				}
				_mutex.release();
			} catch (e:Dynamic) {
				_mutex.release();
				throw e;
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
		_mutex.acquire();
		try {
			var ackCount = 0;

			// Find and remove pending messages
			for (key in _pendingMessages.keys()) {
				if (!key.startsWith('$stream:$group:')) {
					continue;
				}

				var pending = _pendingMessages.get(key);
				var remaining:Array<PendingMessage> = [];

				for (p in pending) {
					if (messageIds.indexOf(p.messageId) == -1) {
						remaining.push(p);
					} else {
						ackCount++;
					}
				}

				if (remaining.length == 0) {
					_pendingMessages.remove(key);
				} else {
					_pendingMessages.set(key, remaining);
				}

				// Update consumer pending count
				if (_consumerGroups.exists(stream)) {
					var groups = _consumerGroups.get(stream);
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

			_mutex.release();
			return ackCount;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function xpending(stream:String, group:String, ?consumer:String):Array<StreamMessage> {
		_mutex.acquire();
		try {
			var result:Array<StreamMessage> = [];

			if (!_streams.exists(stream)) {
				_mutex.release();
				return result;
			}

			var streamMessages = _streams.get(stream);
			var pendingIds:Array<String> = [];

			// Collect pending message IDs
			for (key in _pendingMessages.keys()) {
				if (consumer != null) {
					if (key != '$stream:$group:$consumer') {
						continue;
					}
				} else {
					if (!key.startsWith('$stream:$group:')) {
						continue;
					}
				}

				var pending = _pendingMessages.get(key);
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

			_mutex.release();
			return result;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function xautoclaim(stream:String, group:String, consumer:String, minIdleMs:Int, count:Int = 1):Array<StreamMessage> {
		_mutex.acquire();
		try {
			var claimed:Array<StreamMessage> = [];
			var minIdleSeconds = minIdleMs / 1000.0;
			var now = Sys.time();

			if (!_streams.exists(stream) || !_consumerGroups.exists(stream)) {
				_mutex.release();
				return claimed;
			}

			var groups = _consumerGroups.get(stream);
			if (!groups.exists(group)) {
				_mutex.release();
				return claimed;
			}

			var consumerGroup = groups.get(group);
			var streamMessages = _streams.get(stream);

			// Find stale pending messages from other consumers
			for (key in _pendingMessages.keys()) {
				if (!key.startsWith('$stream:$group:') || key == '$stream:$group:$consumer') {
					continue;
				}

				var oldConsumer = key.substr(key.lastIndexOf(':') + 1);
				var pending = _pendingMessages.get(key);
				var remaining:Array<PendingMessage> = [];

				for (p in pending) {
					var idleTime = now - p.deliveryTime;
					if (idleTime >= minIdleSeconds && claimed.length < count) {
						// Claim this message
						var message = this.findMessageById(streamMessages, p.messageId);
						if (message != null) {
							claimed.push(message);

							// Add to new consumer's pending
							var newKey = '$stream:$group:$consumer';
							if (!_pendingMessages.exists(newKey)) {
								_pendingMessages.set(newKey, []);
							}
							var newPending = _pendingMessages.get(newKey);
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
					_pendingMessages.remove(key);
				} else {
					_pendingMessages.set(key, remaining);
				}

				// Update consumer pending counts
				if (consumerGroup.consumers.exists(oldConsumer)) {
					consumerGroup.consumers.get(oldConsumer).pendingCount = remaining.length;
				}
				if (consumerGroup.consumers.exists(consumer)) {
					var newConsumer = consumerGroup.consumers.get(consumer);
					var newKey = '$stream:$group:$consumer';
					if (_pendingMessages.exists(newKey)) {
						newConsumer.pendingCount = _pendingMessages.get(newKey).length;
					}
				}
			}

			if (claimed.length > 0) {
				HybridLogger.debug('[LocalStreamBroker] Auto-claimed ${claimed.length} messages for $stream:$group:$consumer');
			}

			_mutex.release();
			return claimed;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function xlen(stream:String):Int {
		_mutex.acquire();
		try {
			if (!_streams.exists(stream)) {
				_mutex.release();
				return 0;
			}
			var len = _streams.get(stream).length;
			_mutex.release();
			return len;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function getGroupInfo(stream:String):Array<ConsumerGroupInfo> {
		_mutex.acquire();
		try {
			var result:Array<ConsumerGroupInfo> = [];

			if (!_consumerGroups.exists(stream)) {
				_mutex.release();
				return result;
			}

			var groups = _consumerGroups.get(stream);
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

				var lag = calculateLag(stream, group.lastDeliveredId);

				result.push({
					name: group.name,
					consumers: consumers,
					lastDeliveredId: group.lastDeliveredId,
					totalPending: totalPending,
					lag: lag
				});
			}

			_mutex.release();
			return result;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function deleteConsumer(stream:String, group:String, consumer:String):Int {
		_mutex.acquire();
		try {
			if (!_consumerGroups.exists(stream)) {
				_mutex.release();
				return 0;
			}

			var groups = _consumerGroups.get(stream);
			if (!groups.exists(group)) {
				_mutex.release();
				return 0;
			}

			var consumerGroup = groups.get(group);
			if (!consumerGroup.consumers.exists(consumer)) {
				_mutex.release();
				return 0;
			}

			var pendingCount = consumerGroup.consumers.get(consumer).pendingCount;

			// Remove consumer
			consumerGroup.consumers.remove(consumer);

			// Remove pending messages
			var key = '$stream:$group:$consumer';
			_pendingMessages.remove(key);

			HybridLogger.info('[LocalStreamBroker] Deleted consumer: $stream:$group:$consumer (had $pendingCount pending)');

			_mutex.release();
			return pendingCount;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
		}
	}

	public function xtrim(stream:String, maxLen:Int):Int {
		_mutex.acquire();
		try {
			if (!_streams.exists(stream)) {
				_mutex.release();
				return 0;
			}

			var streamMessages = _streams.get(stream);
			var originalLength = streamMessages.length;

			if (originalLength <= maxLen) {
				_mutex.release();
				return 0;
			}

			// Remove oldest messages
			var toRemove = originalLength - maxLen;
			streamMessages.splice(0, toRemove);

			HybridLogger.info('[LocalStreamBroker] Trimmed stream $stream: removed $toRemove messages');

			_mutex.release();
			return toRemove;
		} catch (e:Dynamic) {
			_mutex.release();
			throw e;
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

		var timestamp1 = Std.parseFloat(parts1[0]);
		var timestamp2 = Std.parseFloat(parts2[0]);

		if (timestamp1 < timestamp2)
			return -1;
		if (timestamp1 > timestamp2)
			return 1;

		var seq1 = Std.parseInt(parts1[1]);
		var seq2 = Std.parseInt(parts2[1]);

		if (seq1 < seq2)
			return -1;
		if (seq1 > seq2)
			return 1;

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

	public function getStreamGroupInfo(stream:String, groupName:String):Null<ConsumerGroupInfo> {
		var infos = getGroupInfo(stream);
		for (info in infos) {
			if (info.name == groupName) return info;
		}
		return null;
	}

	private function calculateLag(stream:String, lastDeliveredId:String):Int {
		_mutex.acquire();
		try {
			if (!_streams.exists(stream)) {
				_mutex.release();
				return 0;
			}
			var messages = _streams.get(stream);
			if (messages.length == 0) {
				_mutex.release();
				return 0;
			}
			
			var lag = 0;
			for (i in 0...messages.length) {
				var msg = messages[messages.length - 1 - i];
				// Compare with lastDeliveredId
				if (compareMessageIds(msg.id, lastDeliveredId) > 0) {
					lag++;
				} else {
					break;
				}
			}
			_mutex.release();
			return lag;
		} catch (e:Dynamic) {
			_mutex.release();
			return 0;
		}
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

