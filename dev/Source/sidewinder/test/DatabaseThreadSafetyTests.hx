package sidewinder.test;

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

import sys.thread.Thread;
import sys.thread.Deque;
import haxe.Timer;

/**
 * Test suite for verifying SqliteDatabaseService thread-safety and optimization.
 */
class DatabaseThreadSafetyTests {

	public static function runAllTests():Void {
		trace("=== Starting Database Thread Safety Tests ===");
		
		testConcurrentReads();
		testConcurrentWrites();
		testReadWriteInterleaving();
		testErrorPropagation();
		
		trace("=== Database Thread Safety Tests Complete ===");
	}

	/**
	 * Test 1: Concurrent reads should use thread-local connections.
	 */
	public static function testConcurrentReads():Void {
		trace("Test 1: Concurrent Reads...");
		var db = DI.get(IDatabaseService);
		var numThreads = 5;
		var results = new Deque<Bool>();

		for (i in 0...numThreads) {
			Thread.create(() -> {
				try {
					var rs = db.read("SELECT 1 as val");
					var success = rs.hasNext() && rs.next().val == 1;
					results.push(success);
				} catch (e:Dynamic) {
					trace('Read thread $i failed: $e');
					results.push(false);
				}
			});
		}

		var allSuccess = true;
		for (i in 0...numThreads) {
			if (!results.pop(true)) allSuccess = false;
		}

		if (allSuccess) {
			trace("✓ Test 1 PASSED: Concurrent reads successful");
		} else {
			trace("✗ Test 1 FAILED: Some concurrent reads failed");
		}
	}

	/**
	 * Test 2: Concurrent writes should be serialized by the writer thread.
	 */
	public static function testConcurrentWrites():Void {
		trace("Test 2: Concurrent Writes...");
		var db = DI.get(IDatabaseService);
		
		// Setup table
		db.write("DROP TABLE IF EXISTS test_writes");
		db.write("CREATE TABLE test_writes (id INTEGER PRIMARY KEY, val TEXT)");

		var numThreads = 10;
		var iterations = 20;
		var done = new Deque<Bool>();

		for (t in 0...numThreads) {
			Thread.create(() -> {
				try {
					for (i in 0...iterations) {
						db.write("INSERT INTO test_writes (val) VALUES (@val)", ["val" => 'thread_${t}_iter_${i}']);
					}
					done.push(true);
				} catch (e:Dynamic) {
					trace('Write thread $t failed: $e');
					done.push(false);
				}
			});
		}

		for (t in 0...numThreads) done.pop(true);

		var rs = db.read("SELECT COUNT(*) as count FROM test_writes");
		var count = rs.next().count;
		var expected = numThreads * iterations;

		if (count == expected) {
			trace('✓ Test 2 PASSED: All $count writes persisted correctly');
		} else {
			trace('✗ Test 2 FAILED: Expected $expected writes, but found $count');
		}
	}

	/**
	 * Test 3: Interleaved reads and writes.
	 */
	public static function testReadWriteInterleaving():Void {
		trace("Test 3: Read/Write Interleaving...");
		var db = DI.get(IDatabaseService);
		
		db.write("DROP TABLE IF EXISTS test_interleave");
		db.write("CREATE TABLE test_interleave (id INTEGER PRIMARY KEY, val INTEGER)");
		db.write("INSERT INTO test_interleave (val) VALUES (0)");

		var stop = false;
		var readSuccess = true;
		var writeSuccess = true;

		// Reader thread
		var reader = Thread.create(() -> {
			while (!stop) {
				try {
					db.read("SELECT val FROM test_interleave");
					Sys.sleep(0.01);
				} catch (e:Dynamic) {
					readSuccess = false;
				}
			}
		});

		// Writer thread
		var writer = Thread.create(() -> {
			for (i in 0...50) {
				try {
					db.write("UPDATE test_interleave SET val = @val", ["val" => i]);
					Sys.sleep(0.01);
				} catch (e:Dynamic) {
					writeSuccess = false;
				}
			}
			stop = true;
		});

		while (!stop) Sys.sleep(0.1);

		if (readSuccess && writeSuccess) {
			trace("✓ Test 3 PASSED: Interleaved reads and writes successful");
		} else {
			trace('✗ Test 3 FAILED: ReadSuccess=$readSuccess, WriteSuccess=$writeSuccess');
		}
	}

	/**
	 * Test 4: Error propagation from writer thread.
	 */
	public static function testErrorPropagation():Void {
		trace("Test 4: Error Propagation...");
		var db = DI.get(IDatabaseService);

		try {
			db.write("INVALID SQL SYNTAX");
			trace("✗ Test 4 FAILED: Invalid SQL did not throw error");
		} catch (e:Dynamic) {
			trace('✓ Test 4 PASSED: Caught expected error: $e');
		}
	}
}
