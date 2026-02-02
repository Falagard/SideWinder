package sidewinder;

/**
 * Example demonstrating the LocalStreamBroker usage.
 * Shows patterns that will work identically with Redis Streams.
 */
class StreamBrokerDemo {
	private var broker:IStreamBroker;
	
	public function new(broker:IStreamBroker) {
		this.broker = broker;
	}
	
	/**
	 * Example 1: Simple fire-and-forget messaging
	 */
	public function simpleExample():Void {
		HybridLogger.info('[StreamDemo] === Simple Fire-and-Forget Example ===');
		
		// Add messages to a stream
		var streamName = "notifications";
		broker.xadd(streamName, {type: "email", to: "user@example.com", subject: "Welcome!"});
		broker.xadd(streamName, {type: "sms", to: "+1234567890", message: "Your code is 1234"});
		broker.xadd(streamName, {type: "push", to: "device123", title: "New message"});
		
		HybridLogger.info('[StreamDemo] Added 3 messages to stream: $streamName');
		HybridLogger.info('[StreamDemo] Stream length: ${broker.xlen(streamName)}');
	}
	
	/**
	 * Example 2: Consumer group processing
	 */
	public function consumerGroupExample():Void {
		HybridLogger.info('[StreamDemo] === Consumer Group Example ===');
		
		var streamName = "tasks";
		var groupName = "workers";
		
		// Create a consumer group
		broker.createGroup(streamName, groupName, "0"); // Start from beginning
		
		// Add some tasks
		broker.xadd(streamName, {task: "send_email", userId: 123});
		broker.xadd(streamName, {task: "generate_report", reportId: 456});
		broker.xadd(streamName, {task: "process_payment", orderId: 789});
		
		// Worker 1 reads and processes messages
		var messages1 = broker.xreadgroup(groupName, "worker-1", streamName, 2); // Read up to 2
		HybridLogger.info('[StreamDemo] Worker-1 received ${messages1.length} messages');
		
		for (msg in messages1) {
			HybridLogger.info('[StreamDemo] Processing: ${msg.id} -> ${msg.data}');
			// Simulate processing
			Sys.sleep(0.1);
			// Acknowledge
			broker.xack(streamName, groupName, [msg.id]);
		}
		
		// Worker 2 reads remaining messages
		var messages2 = broker.xreadgroup(groupName, "worker-2", streamName, 10);
		HybridLogger.info('[StreamDemo] Worker-2 received ${messages2.length} messages');
		
		for (msg in messages2) {
			HybridLogger.info('[StreamDemo] Processing: ${msg.id} -> ${msg.data}');
			broker.xack(streamName, groupName, [msg.id]);
		}
		
		// Check group info
		var groupInfo = broker.getGroupInfo(streamName);
		for (info in groupInfo) {
			HybridLogger.info('[StreamDemo] Group: ${info.name}, Consumers: ${info.consumers.length}, Pending: ${info.totalPending}');
		}
	}
	
	/**
	 * Example 3: Auto-claim stale messages
	 */
	public function autoClaimExample():Void {
		HybridLogger.info('[StreamDemo] === Auto-Claim Example ===');
		
		var streamName = "jobs";
		var groupName = "processors";
		
		broker.createGroup(streamName, groupName);
		
		// Add messages
		broker.xadd(streamName, {job: "backup_database"});
		broker.xadd(streamName, {job: "cleanup_logs"});
		
		// Consumer 1 reads but doesn't acknowledge (simulating a crash/hang)
		var messages = broker.xreadgroup(groupName, "processor-1", streamName, 10);
		HybridLogger.info('[StreamDemo] Processor-1 received ${messages.length} messages but crashed!');
		
		// Simulate time passing
		Sys.sleep(0.1);
		
		// Consumer 2 auto-claims stale messages (older than 50ms)
		var claimed = broker.xautoclaim(streamName, groupName, "processor-2", 50, 10);
		HybridLogger.info('[StreamDemo] Processor-2 auto-claimed ${claimed.length} stale messages');
		
		for (msg in claimed) {
			HybridLogger.info('[StreamDemo] Recovered and processing: ${msg.id} -> ${msg.data}');
			broker.xack(streamName, groupName, [msg.id]);
		}
	}
	
	/**
	 * Example 4: Long polling / blocking reads
	 */
	public function blockingReadExample():Void {
		HybridLogger.info('[StreamDemo] === Blocking Read Example ===');
		
		var streamName = "events";
		var groupName = "listeners";
		
		broker.createGroup(streamName, groupName);
		
		// Start a consumer that blocks waiting for messages
		sys.thread.Thread.create(() -> {
			HybridLogger.info('[StreamDemo] Listener starting (will block for 2 seconds)...');
			var messages = broker.xreadgroup(groupName, "listener-1", streamName, 1, 2000); // Block 2s
			
			if (messages.length > 0) {
				for (msg in messages) {
					HybridLogger.info('[StreamDemo] Listener received: ${msg.id} -> ${msg.data}');
					broker.xack(streamName, groupName, [msg.id]);
				}
			} else {
				HybridLogger.info('[StreamDemo] Listener timeout - no messages received');
			}
		});
		
		// Give the thread time to start blocking
		Sys.sleep(0.5);
		
		// Add a message while consumer is blocked
		HybridLogger.info('[StreamDemo] Adding message while consumer is blocked...');
		broker.xadd(streamName, {event: "user_signup", userId: 999});
		
		// Wait for consumer to process
		Sys.sleep(1.0);
	}
	
	/**
	 * Example 5: Multiple streams and groups
	 */
	public function multiStreamExample():Void {
		HybridLogger.info('[StreamDemo] === Multi-Stream Example ===');
		
		// Email stream with different priority groups
		broker.createGroup("emails", "high-priority", "0");
		broker.createGroup("emails", "low-priority", "0");
		
		broker.xadd("emails", {priority: "high", subject: "URGENT: Server down"});
		broker.xadd("emails", {priority: "low", subject: "Newsletter"});
		
		// SMS stream
		broker.createGroup("sms", "sms-workers", "0");
		broker.xadd("sms", {to: "+1234567890", text: "Your code is 5678"});
		
		// Process high priority emails first
		var highPriority = broker.xreadgroup("high-priority", "email-worker-1", "emails", 10);
		HybridLogger.info('[StreamDemo] High priority emails: ${highPriority.length}');
		
		// Process SMS
		var smsMessages = broker.xreadgroup("sms-workers", "sms-worker-1", "sms", 10);
		HybridLogger.info('[StreamDemo] SMS messages: ${smsMessages.length}');
		
		// Acknowledge all
		for (msg in highPriority) {
			broker.xack("emails", "high-priority", [msg.id]);
		}
		for (msg in smsMessages) {
			broker.xack("sms", "sms-workers", [msg.id]);
		}
	}
	
	/**
	 * Run all examples
	 */
	public function runAll():Void {
		simpleExample();
		HybridLogger.info("");
		
		consumerGroupExample();
		HybridLogger.info("");
		
		autoClaimExample();
		HybridLogger.info("");
		
		blockingReadExample();
		HybridLogger.info("");
		
		multiStreamExample();
		HybridLogger.info("");
		
		HybridLogger.info('[StreamDemo] === All examples completed ===');
	}
}
