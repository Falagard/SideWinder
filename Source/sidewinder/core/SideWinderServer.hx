package sidewinder.core;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;

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




