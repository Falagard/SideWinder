package sidewinder;

import hx.injection.Service;

/**
 * Message broker interface for WebSocket-like messaging.
 * This interface is designed to be implementation-agnostic,
 * allowing easy migration from polling to WebSockets.
 */
interface IMessageBroker extends Service {
	/**
	 * Subscribe a client to receive messages.
	 * @param clientId Unique identifier for the client
	 */
	public function subscribe(clientId:String):Void;

	/**
	 * Unsubscribe a client from receiving messages.
	 * @param clientId Unique identifier for the client
	 */
	public function unsubscribe(clientId:String):Void;

	/**
	 * Send a message to a specific client.
	 * @param clientId Target client identifier
	 * @param message Message content (typically JSON string)
	 */
	public function sendToClient(clientId:String, message:String):Void;

	/**
	 * Broadcast a message to all connected clients.
	 * @param message Message content (typically JSON string)
	 */
	public function broadcast(message:String):Void;

	/**
	 * Get pending messages for a client (blocking call for long-polling).
	 * @param clientId Client identifier
	 * @param timeout Maximum time to wait for messages (in seconds)
	 * @return Array of pending messages, or empty array if timeout
	 */
	public function getMessages(clientId:String, timeout:Float):Array<String>;

	/**
	 * Check if a client is currently subscribed.
	 * @param clientId Client identifier
	 * @return True if client is subscribed
	 */
	public function isSubscribed(clientId:String):Bool;

	/**
	 * Get the number of currently connected clients.
	 * @return Number of active clients
	 */
	public function getClientCount():Int;
}
