package sidewinder;

/**
 * Interface for handling WebSocket connections
 */
interface IWebSocketHandler {
    /**
     * Called when a new WebSocket connection is established
     * @return True to accept the connection, false to reject
     */
    function onConnect():Bool;
    
    /**
     * Called when the WebSocket is ready to send/receive data
     * @param conn Connection handle
     */
    function onReady(conn:Dynamic):Void;
    
    /**
     * Called when data is received from the WebSocket
     * @param conn Connection handle
     * @param flags WebSocket flags (FIN, opcode, etc.)
     * @param data Data received
     * @param length Length of data
     */
    function onData(conn:Dynamic, flags:Int, data:hl.Bytes, length:Int):Void;
    
    /**
     * Called when the WebSocket connection is closed
     * @param conn Connection handle
     */
    function onClose(conn:Dynamic):Void;
}

/**
 * WebSocket opcode constants
 */
class WebSocketOpcode {
    public static inline var CONTINUATION = 0x0;
    public static inline var TEXT = 0x1;
    public static inline var BINARY = 0x2;
    public static inline var CLOSE = 0x8;
    public static inline var PING = 0x9;
    public static inline var PONG = 0xA;
}

/**
 * WebSocket close status codes
 */
class WebSocketCloseCode {
    public static inline var NORMAL = 1000;
    public static inline var GOING_AWAY = 1001;
    public static inline var PROTOCOL_ERROR = 1002;
    public static inline var UNSUPPORTED_DATA = 1003;
    public static inline var NO_STATUS = 1005;
    public static inline var ABNORMAL = 1006;
    public static inline var INVALID_PAYLOAD = 1007;
    public static inline var POLICY_VIOLATION = 1008;
    public static inline var MESSAGE_TOO_BIG = 1009;
    public static inline var INTERNAL_ERROR = 1011;
}
