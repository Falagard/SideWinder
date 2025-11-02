package sidewinder;

import snake.server.*;
import snake.socket.*;
import sys.net.Host;
import sys.net.Socket;
import snake.http.*;

class SideWinderServer extends HTTPServer {
	private var directory:String;

	public function new(serverHost:Host, serverPort:Int, requestHandlerClass:Class<BaseRequestHandler>, bindAndActivate:Bool = true, ?directory:String) {
		this.directory = directory;
		super(serverHost, serverPort, requestHandlerClass, bindAndActivate);
		Sys.print('Serving HTTP on ${serverAddress.host} port ${serverAddress.port} (http://${serverAddress.host}:${serverAddress.port})\n');
        threading = true;
        requestQueueSize = 128;
	}
}
