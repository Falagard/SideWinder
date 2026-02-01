package sidewinder.native;

/**
 * HashLink native bindings for CivetWeb
 * Low-level interface to the CivetWeb C library
 */
@:hlNative("civetweb")
class CivetWebNative {
    /**
     * Opaque server handle
     */
    public var handle:hl.Abstract<"hl_civetweb_server">;
    
    /**
     * Create a new CivetWeb server instance
     * @param host Host address (e.g., "127.0.0.1")
     * @param port Port number
     * @param documentRoot Optional document root for static files
     * @return Server handle
     */
    @:hlNative("civetweb", "create")
    public static function create(host:hl.Bytes, port:Int, documentRoot:hl.Bytes):CivetWebNative {
        return null;
    }
    
    /**
     * Start the server with a request handler
     * @param server Server handle
     * @param handler Request handler callback
     * @return True if started successfully
     */
    @:hlNative("civetweb", "start")
    public static function start(server:CivetWebNative, handler:Dynamic->Void):Bool {
        return false;
    }
    
    /**
     * Stop the server
     * @param server Server handle
     */
    @:hlNative("civetweb", "stop")
    public static function stop(server:CivetWebNative):Void {
    }
    
    /**
     * Check if server is running
     * @param server Server handle
     * @return True if running
     */
    @:hlNative("civetweb", "is_running")
    public static function isRunning(server:CivetWebNative):Bool {
        return false;
    }
    
    /**
     * Get server port
     * @param server Server handle
     * @return Port number
     */
    @:hlNative("civetweb", "get_port")
    public static function getPort(server:CivetWebNative):Int {
        return 0;
    }
    
    /**
     * Get server host
     * @param server Server handle
     * @return Host address
     */
    @:hlNative("civetweb", "get_host")
    public static function getHost(server:CivetWebNative):hl.Bytes {
        return null;
    }
    
    /**
     * Free server resources
     * @param server Server handle
     */
    @:hlNative("civetweb", "free")
    public static function free(server:CivetWebNative):Void {
    }
}

/**
 * HTTP request data from CivetWeb
 */
typedef CivetWebRequest = {
    var uri:String;
    var method:String;
    var body:String;
    var bodyLength:Int;
    var queryString:String;
    var remoteAddr:String;
}

/**
 * HTTP response data for CivetWeb
 */
typedef CivetWebResponse = {
    var statusCode:Int;
    var contentType:String;
    var body:String;
    var bodyLength:Int;
}
