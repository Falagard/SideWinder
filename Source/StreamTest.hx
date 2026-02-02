package;

import sidewinder.*;

/**
 * Simple test program for the Stream Broker system.
 * Run with: lime test hl -Dstream_test
 */
class StreamTest {
	static function main() {
		trace("=== Stream Broker Test Suite ===\n");
		
		// Initialize logger
		HybridLogger.init();
		
		// Create broker instance
		var broker = new LocalStreamBroker();
		
		// Run tests
		testBasicOperations(broker);
		testConsumerGroups(broker);
		testPendingMessages(broker);
		testAutoClaim(broker);
		testTrimming(broker);
		
		trace("\n=== All tests completed ===");
	}
	
	static function testBasicOperations(broker:IStreamBroker):Void {
		trace("Test 1: Basic Operations");
		
		// Add messages
		var id1 = broker.xadd("test-stream", {message: "Hello"});
		var id2 = broker.xadd("test-stream", {message: "World"});
		
		assert(id1 != null, "Message ID should not be null");
		assert(id2 != null, "Message ID should not be null");
		assert(id1 != id2, "Message IDs should be unique");
		
		// Check length
		var length = broker.xlen("test-stream");
		assert(length == 2, 'Expected length 2, got $length');
		
		trace("  ✓ xadd and xlen working");
	}
	
	static function testConsumerGroups(broker:IStreamBroker):Void {
		trace("Test 2: Consumer Groups");
		
		var stream = "group-test";
		var group = "test-group";
		
		// Add messages
		broker.xadd(stream, {task: "task1"});
		broker.xadd(stream, {task: "task2"});
		broker.xadd(stream, {task: "task3"});
		
		// Create group
		broker.createGroup(stream, group, "0");
		
		// Read messages
		var messages1 = broker.xreadgroup(group, "consumer1", stream, 2);
		assert(messages1.length == 2, 'Expected 2 messages, got ${messages1.length}');
		
		var messages2 = broker.xreadgroup(group, "consumer2", stream, 2);
		assert(messages2.length == 1, 'Expected 1 message, got ${messages2.length}');
		
		// Verify different consumers got different messages
		assert(messages1[0].id != messages2[0].id, "Consumers should get different messages");
		
		trace("  ✓ Consumer groups distributing messages correctly");
	}
	
	static function testPendingMessages(broker:IStreamBroker):Void {
		trace("Test 3: Pending Messages");
		
		var stream = "pending-test";
		var group = "pending-group";
		
		broker.xadd(stream, {data: "test"});
		broker.createGroup(stream, group, "0");
		
		// Read without acking
		var messages = broker.xreadgroup(group, "consumer1", stream, 1);
		assert(messages.length == 1, "Should read 1 message");
		
		// Check pending
		var pending = broker.xpending(stream, group);
		assert(pending.length == 1, 'Expected 1 pending, got ${pending.length}');
		
		// Acknowledge
		var acked = broker.xack(stream, group, [messages[0].id]);
		assert(acked == 1, 'Expected 1 acked, got $acked');
		
		// Check pending again
		pending = broker.xpending(stream, group);
		assert(pending.length == 0, 'Expected 0 pending after ack, got ${pending.length}');
		
		trace("  ✓ Pending messages tracked and acknowledged correctly");
	}
	
	static function testAutoClaim(broker:IStreamBroker):Void {
		trace("Test 4: Auto-Claim");
		
		var stream = "claim-test";
		var group = "claim-group";
		
		broker.xadd(stream, {data: "test1"});
		broker.xadd(stream, {data: "test2"});
		broker.createGroup(stream, group, "0");
		
		// Consumer1 reads but doesn't ack
		var messages = broker.xreadgroup(group, "consumer1", stream, 2);
		assert(messages.length == 2, "Consumer1 should read 2 messages");
		
		// Wait a bit
		Sys.sleep(0.15);
		
		// Consumer2 auto-claims stale messages (idle > 100ms)
		var claimed = broker.xautoclaim(stream, group, "consumer2", 100, 10);
		assert(claimed.length == 2, 'Expected to claim 2 messages, got ${claimed.length}');
		
		// Ack as consumer2
		broker.xack(stream, group, [claimed[0].id, claimed[1].id]);
		
		// Verify no pending
		var pending = broker.xpending(stream, group);
		assert(pending.length == 0, 'Expected 0 pending after claim and ack, got ${pending.length}');
		
		trace("  ✓ Auto-claim working correctly");
	}
	
	static function testTrimming(broker:IStreamBroker):Void {
		trace("Test 5: Stream Trimming");
		
		var stream = "trim-test";
		
		// Add 10 messages
		for (i in 0...10) {
			broker.xadd(stream, {index: i});
		}
		
		assert(broker.xlen(stream) == 10, "Should have 10 messages");
		
		// Trim to 5
		var removed = broker.xtrim(stream, 5);
		assert(removed == 5, 'Expected to remove 5, removed $removed');
		assert(broker.xlen(stream) == 5, 'Expected 5 messages after trim, got ${broker.xlen(stream)}');
		
		trace("  ✓ Stream trimming working correctly");
	}
	
	static function assert(condition:Bool, message:String):Void {
		if (!condition) {
			trace('  ✗ FAILED: $message');
			throw 'Assertion failed: $message';
		}
	}
}
