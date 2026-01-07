package sidewinder;

/**
 * Message client interface that mimics WebSocket API.
 * This interface allows easy migration from polling to WebSockets.
 */
interface IMessageClient {
	/**
	 * Establish connection to the server.
	 * Triggers onConnect when successful.
	 */
	public function connect():Void;

	/**
	 * Close the connection to the server.
	 * Triggers onDisconnect.
	 */
	public function disconnect():Void;

	/**
	 * Send a message to the server.
	 * @param message Message content (typically JSON string)
	 */
	public function send(message:String):Void;

	/**
	 * Check if currently connected.
	 * @return True if connected
	 */
	public function isConnected():Bool;

	/**
	 * Get the unique client ID.
	 * @return Client identifier
	 */
	public function getClientId():String;

	// Event handlers (set these to handle events)

	/**
	 * Called when a message is received from the server.
	 */
	public var onMessage:(message:String) -> Void;

	/**
	 * Called when connection is established.
	 */
	public var onConnect:() -> Void;

	/**
	 * Called when connection is closed.
	 */
	public var onDisconnect:() -> Void;

	/**
	 * Called when an error occurs.
	 */
	public var onError:(error:String) -> Void;
}
