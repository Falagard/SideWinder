package;

import sidewinder.PollingClient;
import sidewinder.IMessageClient;
import haxe.Json;
import haxe.Timer;

/**
 * Example demonstrating how to use the PollingClient.
 * This shows the WebSocket-like API for receiving server messages.
 */
class PollingClientDemo {
	public static function main() {
		trace("=== Polling Client Demo ===");
		trace("This demo shows how to use the PollingClient to receive messages from the server.");
		trace("");

		// Create a polling client
		var client:IMessageClient = new PollingClient("http://127.0.0.1:8000");

		// Set up event handlers (WebSocket-like API)
		client.onConnect = function() {
			trace("[Demo] ✓ Connected to server!");
			trace("[Demo] Client ID: " + client.getClientId());
			trace("[Demo] Waiting for messages...");
			trace("");
		};

		client.onMessage = function(message:String) {
			try {
				// Parse the JSON message
				var data:Dynamic = Json.parse(message);
				trace("[Demo] 📨 Message received:");
				trace("       Type: " + data.type);
				trace("       Counter: " + data.counter);
				trace("       Message: " + data.message);
				trace("       Timestamp: " + data.timestamp);
				trace("");
			} catch (e:Dynamic) {
				trace("[Demo] 📨 Raw message: " + message);
				trace("");
			}
		};

		client.onDisconnect = function() {
			trace("[Demo] ✗ Disconnected from server");
			trace("");
		};

		client.onError = function(error:String) {
			trace("[Demo] ⚠ Error: " + error);
			trace("");
		};

		// Connect to the server
		trace("[Demo] Connecting to server...");
		client.connect();

		// Keep the application running
		trace("[Demo] Press Ctrl+C to exit");
		trace("");

		// Optionally disconnect after some time (for testing)
		// Timer.delay(() -> {
		// 	trace("[Demo] Disconnecting...");
		// 	client.disconnect();
		// }, 60000); // 60 seconds

		// Keep main thread alive
		while (true) {
			Sys.sleep(1.0);
		}
	}
}
