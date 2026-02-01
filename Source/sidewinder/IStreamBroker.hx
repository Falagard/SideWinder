package sidewinder;

import hx.injection.Service;

/**
 * Message entry in a stream.
 * Modeled after Redis Stream entries.
 */
typedef StreamMessage = {
	/** Unique message ID (auto-generated, format: timestamp-sequence) */
	var id:String;
	
	/** Message payload */
	var data:Dynamic;
	
	/** Timestamp when message was added */
	var timestamp:Float;
}

/**
 * Consumer information within a consumer group.
 */
typedef ConsumerInfo = {
	/** Consumer name */
	var name:String;
	
	/** Number of pending messages for this consumer */
	var pending:Int;
	
	/** Last activity timestamp */
	var lastActivity:Float;
}

/**
 * Consumer group information.
 */
typedef ConsumerGroupInfo = {
	/** Group name */
	var name:String;
	
	/** List of consumers in this group */
	var consumers:Array<ConsumerInfo>;
	
	/** Last delivered message ID */
	var lastDeliveredId:String;
	
	/** Number of pending messages across all consumers */
	var totalPending:Int;
}

/**
 * Stream broker interface for fire-and-forget message handling.
 * Modeled after Redis Streams and Consumer Groups for easy future migration.
 * 
 * Key concepts:
 * - Stream: Named message queue
 * - Consumer Group: Logical group of consumers that process messages from a stream
 * - Consumer: Individual processor within a group (receives unique messages)
 * - Pending: Messages delivered but not yet acknowledged
 * - Auto-claim: Mechanism to reassign stale messages to active consumers
 */
interface IStreamBroker extends Service {
	/**
	 * Add a message to a stream (fire-and-forget).
	 * Similar to Redis XADD.
	 * 
	 * @param stream Stream name
	 * @param data Message payload
	 * @return Generated message ID
	 */
	public function xadd(stream:String, data:Dynamic):String;
	
	/**
	 * Create a consumer group for a stream.
	 * Similar to Redis XGROUP CREATE.
	 * 
	 * @param stream Stream name
	 * @param group Consumer group name
	 * @param startId Message ID to start from ("0" for beginning, "$" for new messages only)
	 */
	public function createGroup(stream:String, group:String, startId:String = "$"):Void;
	
	/**
	 * Delete a consumer group.
	 * Similar to Redis XGROUP DESTROY.
	 * 
	 * @param stream Stream name
	 * @param group Consumer group name
	 */
	public function deleteGroup(stream:String, group:String):Void;
	
	/**
	 * Read messages from a stream as a consumer in a group.
	 * Similar to Redis XREADGROUP.
	 * 
	 * @param group Consumer group name
	 * @param consumer Consumer name
	 * @param stream Stream name
	 * @param count Maximum number of messages to read
	 * @param blockMs Time to block waiting for messages (0 = no blocking, null = block indefinitely)
	 * @return Array of messages
	 */
	public function xreadgroup(group:String, consumer:String, stream:String, count:Int = 1, ?blockMs:Null<Int>):Array<StreamMessage>;
	
	/**
	 * Acknowledge that a message has been processed.
	 * Similar to Redis XACK.
	 * 
	 * @param stream Stream name
	 * @param group Consumer group name
	 * @param messageIds Array of message IDs to acknowledge
	 * @return Number of messages acknowledged
	 */
	public function xack(stream:String, group:String, messageIds:Array<String>):Int;
	
	/**
	 * Get pending messages for a consumer group.
	 * Similar to Redis XPENDING.
	 * 
	 * @param stream Stream name
	 * @param group Consumer group name
	 * @param consumer Optional consumer name to filter by
	 * @return Array of pending messages
	 */
	public function xpending(stream:String, group:String, ?consumer:String):Array<StreamMessage>;
	
	/**
	 * Claim pending messages that have been idle for too long.
	 * Similar to Redis XAUTOCLAIM.
	 * 
	 * @param stream Stream name
	 * @param group Consumer group name
	 * @param consumer Consumer name to claim messages for
	 * @param minIdleMs Minimum idle time in milliseconds
	 * @param count Maximum number of messages to claim
	 * @return Array of claimed messages
	 */
	public function xautoclaim(stream:String, group:String, consumer:String, minIdleMs:Int, count:Int = 1):Array<StreamMessage>;
	
	/**
	 * Get length of a stream.
	 * Similar to Redis XLEN.
	 * 
	 * @param stream Stream name
	 * @return Number of messages in stream
	 */
	public function xlen(stream:String):Int;
	
	/**
	 * Get information about consumer groups for a stream.
	 * Similar to Redis XINFO GROUPS.
	 * 
	 * @param stream Stream name
	 * @return Array of consumer group information
	 */
	public function getGroupInfo(stream:String):Array<ConsumerGroupInfo>;
	
	/**
	 * Delete a consumer from a consumer group.
	 * Similar to Redis XGROUP DELCONSUMER.
	 * 
	 * @param stream Stream name
	 * @param group Consumer group name
	 * @param consumer Consumer name
	 * @return Number of pending messages the consumer had
	 */
	public function deleteConsumer(stream:String, group:String, consumer:String):Int;
	
	/**
	 * Trim a stream to a maximum length (optional, for resource management).
	 * Similar to Redis XTRIM.
	 * 
	 * @param stream Stream name
	 * @param maxLen Maximum number of messages to keep
	 * @return Number of messages deleted
	 */
	public function xtrim(stream:String, maxLen:Int):Int;
}
