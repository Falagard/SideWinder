package sidewinder;

/**
 * Web server abstraction interface.
 * Allows swapping between different HTTP server implementations (snake-server, CivetWeb, etc.)
 */
interface IWebServer {
	/**
	 * Start the web server and begin accepting requests.
	 * This method should be called once during application initialization.
	 */
	public function start():Void;

	/**
	 * Handle pending HTTP requests.
	 * Should be called regularly (e.g., in the main update loop) to process incoming connections.
	 * For threaded servers, this may be a no-op.
	 */
	public function handleRequest():Void;

	/**
	 * Stop the web server and clean up resources.
	 */
	public function stop():Void;

	/**
	 * Get the server's host address.
	 * @return Host address (e.g., "127.0.0.1")
	 */
	public function getHost():String;

	/**
	 * Get the server's port number.
	 * @return Port number (e.g., 8000)
	 */
	public function getPort():Int;

	/**
	 * Check if the server is currently running.
	 * @return True if server is running
	 */
	public function isRunning():Bool;
}
