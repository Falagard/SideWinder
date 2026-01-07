package sidewinder;

import haxe.Http;
import haxe.Json;

#if sys
import sys.thread.Thread;
import sys.thread.Mutex;
#end

#if (js || html5)
import haxe.Timer;
#end

/**
 * Cross-platform polling-based implementation of IMessageClient.
 * Works on both sys targets (using threads) and HTML5 (using timers).
 * Automatically polls the server for messages and handles reconnection.
 */
class PollingClient implements IMessageClient {
	private static final POLL_TIMEOUT = 30.0; // 30 seconds
	private static final RECONNECT_DELAY = 2.0; // 2 seconds
	private static final MAX_RECONNECT_DELAY = 30.0; // 30 seconds
	private static final HTML5_POLL_INTERVAL = 100; // 100ms for HTML5

	private var baseUrl:String;
	private var clientId:String;
	private var connected:Bool;
	private var shouldRun:Bool;
	private var reconnectDelay:Float;
	
	#if sys
	private var pollingThread:Thread;
	private var mutex:Mutex;
	#end
	
	#if (js || html5)
	private var pollingTimer:Timer;
	private var isPolling:Bool;
	#end

	// Event handlers
	public var onMessage:(message:String) -> Void;
	public var onConnect:() -> Void;
	public var onDisconnect:() -> Void;
	public var onError:(error:String) -> Void;

	/**
	 * Create a new polling client.
	 * @param baseUrl Server base URL (e.g., "http://localhost:8000")
	 * @param clientId Optional client ID (auto-generated if not provided)
	 */
	public function new(baseUrl:String, ?clientId:String) {
		this.baseUrl = baseUrl;
		this.clientId = clientId != null ? clientId : generateClientId();
		this.connected = false;
		this.shouldRun = false;
		this.reconnectDelay = RECONNECT_DELAY;
		
		#if sys
		this.mutex = new Mutex();
		#end
		
		#if (js || html5)
		this.isPolling = false;
		#end

		// Default no-op handlers
		this.onMessage = function(msg:String) {};
		this.onConnect = function() {};
		this.onDisconnect = function() {};
		this.onError = function(err:String) {};

		trace('[PollingClient] Created with clientId: $clientId');
	}

	public function connect():Void {
		#if sys
		mutex.acquire();
		#end
		
		if (shouldRun) {
			#if sys
			mutex.release();
			#end
			trace('[PollingClient] Already connected or connecting');
			return;
		}
		shouldRun = true;
		
		#if sys
		mutex.release();
		#end

		// Subscribe to the server
		subscribeToServer();

		#if sys
		// Start polling thread (sys targets)
		pollingThread = Thread.create(() -> {
			pollingLoop();
		});
		#elseif (js || html5)
		// Start polling timer (HTML5 targets)
		pollingTimer = new Timer(HTML5_POLL_INTERVAL);
		pollingTimer.run = () -> {
			if (shouldRun && connected && !isPolling) {
				pollOnce();
			}
		};
		#end

		trace('[PollingClient] Connection initiated for $clientId');
	}

	public function disconnect():Void {
		#if sys
		mutex.acquire();
		#end
		
		if (!shouldRun) {
			#if sys
			mutex.release();
			#end
			return;
		}
		shouldRun = false;
		
		#if sys
		mutex.release();
		#end
		
		#if (js || html5)
		if (pollingTimer != null) {
			pollingTimer.stop();
			pollingTimer = null;
		}
		#end

		// Unsubscribe from server
		unsubscribeFromServer();

		// Update connection state
		setConnected(false);

		trace('[PollingClient] Disconnected $clientId');
	}

	public function send(message:String):Void {
		if (!connected) {
			trace('[PollingClient] Cannot send message, not connected');
			callOnError("Not connected");
			return;
		}

		try {
			var url = baseUrl + '/poll/message';
			var http = new Http(url);
			http.setHeader("Content-Type", "application/json");
			http.setPostData(Json.stringify({
				clientId: clientId,
				message: message
			}));

			http.onError = function(error:String) {
				trace('[PollingClient] Send error: $error');
				callOnError(error);
			};

			http.onData = function(data:String) {
				trace('[PollingClient] Message sent successfully');
			};

			http.request(true); // POST
		} catch (e:Dynamic) {
			trace('[PollingClient] Send exception: $e');
			callOnError(Std.string(e));
		}
	}

	public function isConnected():Bool {
		#if sys
		mutex.acquire();
		var result = connected;
		mutex.release();
		return result;
		#else
		return connected;
		#end
	}

	public function getClientId():String {
		return clientId;
	}

	// Private methods

	private function subscribeToServer():Void {
		try {
			var url = baseUrl + '/poll/subscribe';
			var http = new Http(url);
			http.setHeader("Content-Type", "application/json");
			http.setPostData(Json.stringify({ clientId: clientId }));

			http.onError = function(error:String) {
				trace('[PollingClient] Subscribe error: $error');
				callOnError(error);
				scheduleReconnect();
			};

			http.onData = function(data:String) {
				trace('[PollingClient] Subscribed successfully: $clientId');
				setConnected(true);
				reconnectDelay = RECONNECT_DELAY; // Reset reconnect delay
			};

			http.request(true); // POST
		} catch (e:Dynamic) {
			trace('[PollingClient] Subscribe exception: $e');
			callOnError(Std.string(e));
			scheduleReconnect();
		}
	}

	private function unsubscribeFromServer():Void {
		try {
			var url = baseUrl + '/poll/unsubscribe/' + clientId;
			var http = new Http(url);
			http.setHeader("Content-Type", "application/json");
			http.setPostData("{}");

			http.onError = function(error:String) {
				trace('[PollingClient] Unsubscribe error: $error');
			};

			http.onData = function(data:String) {
				trace('[PollingClient] Unsubscribed successfully: $clientId');
			};

			http.request(true); // POST
		} catch (e:Dynamic) {
			trace('[PollingClient] Unsubscribe exception: $e');
		}
	}

	#if sys
	private function pollingLoop():Void {
		while (shouldRun) {
			if (!connected) {
				Sys.sleep(1.0);
				continue;
			}

			pollOnce();
		}

		trace('[PollingClient] Polling loop ended for $clientId');
	}
	#end

	private function pollOnce():Void {
		#if (js || html5)
		if (isPolling) return; // Prevent concurrent polls
		isPolling = true;
		#end

		try {
			var url = baseUrl + '/poll/' + clientId;
			var http = new Http(url);

			http.onError = function(error:String) {
				#if (js || html5)
				isPolling = false;
				#end
				trace('[PollingClient] Poll error: $error');
				callOnError(error);
				setConnected(false);
				scheduleReconnect();
			};

			http.onData = function(data:String) {
				#if (js || html5)
				isPolling = false;
				#end
				try {
					var response:{ messages:Array<String> } = Json.parse(data);
					if (response.messages != null && response.messages.length > 0) {
						for (msg in response.messages) {
							callOnMessage(msg);
						}
					}
				} catch (e:Dynamic) {
					trace('[PollingClient] Parse error: $e');
					callOnError(Std.string(e));
				}
			};

			http.request(false); // GET
		} catch (e:Dynamic) {
			#if (js || html5)
			isPolling = false;
			#end
			trace('[PollingClient] Polling exception: $e');
			callOnError(Std.string(e));
			setConnected(false);
			scheduleReconnect();
		}
	}

	private function scheduleReconnect():Void {
		if (!shouldRun) return;

		trace('[PollingClient] Reconnecting in $reconnectDelay seconds...');
		
		#if sys
		Sys.sleep(reconnectDelay);
		#elseif (js || html5)
		Timer.delay(() -> {
			if (shouldRun) {
				subscribeToServer();
			}
		}, Std.int(reconnectDelay * 1000));
		return; // Exit early for HTML5 to prevent immediate reconnect
		#end

		// Exponential backoff
		reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY);

		if (shouldRun) {
			subscribeToServer();
		}
	}

	private function setConnected(value:Bool):Void {
		#if sys
		mutex.acquire();
		#end
		
		var wasConnected = connected;
		connected = value;
		
		#if sys
		mutex.release();
		#end

		// Trigger events outside of mutex
		if (value && !wasConnected) {
			callOnConnect();
		} else if (!value && wasConnected) {
			callOnDisconnect();
		}
	}

	private function callOnMessage(message:String):Void {
		try {
			onMessage(message);
		} catch (e:Dynamic) {
			trace('[PollingClient] Error in onMessage handler: $e');
		}
	}

	private function callOnConnect():Void {
		try {
			onConnect();
		} catch (e:Dynamic) {
			trace('[PollingClient] Error in onConnect handler: $e');
		}
	}

	private function callOnDisconnect():Void {
		try {
			onDisconnect();
		} catch (e:Dynamic) {
			trace('[PollingClient] Error in onDisconnect handler: $e');
		}
	}

	private function callOnError(error:String):Void {
		try {
			onError(error);
		} catch (e:Dynamic) {
			trace('[PollingClient] Error in onError handler: $e');
		}
	}

	private static function generateClientId():String {
		var chars = "abcdefghijklmnopqrstuvwxyz0123456789";
		var id = "";
		for (i in 0...16) {
			id += chars.charAt(Std.random(chars.length));
		}
		return "client_" + id;
	}
}
