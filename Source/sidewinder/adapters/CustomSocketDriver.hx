package sidewinder.adapters;

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

import hx.well.http.driver.socket.SocketDriver;
import hx.well.http.driver.socket.SocketRequestParser;
import hx.well.http.driver.socket.SocketInput;
import hx.well.http.driver.socket.SocketWebSocketHandler;
import hx.well.http.RequestStatic;
import sys.net.Socket;
import haxe.Http;

@:access(hx.well.http.driver.socket.SocketDriver)
class CustomSocketDriver extends SocketDriver {
	private var adapter:HxWellAdapter;

	public function new(config, adapter) {
		super(config);
		this.adapter = adapter;
	}

	override public function process(socket:Socket):Void {
		// Run in background threadpool provided by SocketDriver
		@:privateAccess executor.submit(() -> {
			try {
				socket.setTimeout(30);
				var hxReq = hx.well.http.driver.socket.SocketRequestParser.parseFromSocket(socket);

				// Check for WebSocket upgrade
				var upgrade = hxReq.header("Upgrade");
				if (upgrade != null && upgrade.toLowerCase() == "websocket") {
					var bridge = new HxWellWebSocketBridge(adapter);
					// This blocks the background thread and handles the message loop
					hx.well.http.driver.socket.SocketWebSocketHandler.upgrade(socket, hxReq, bridge);
					return;
				}
				
				// Handle body parsing if Content-Length is present
				var contentLen = hxReq.header("Content-Length");
				
				if (contentLen != null) {
					var len = Std.parseInt(contentLen);
					if (len > 0) {
						var input = new hx.well.http.driver.socket.SocketInput(socket);
						input.length = len;
						
						// Set static context so hxwell internal parsers can find the request
						hx.well.http.RequestStatic.set(hxReq);
						try {
							hx.well.http.driver.socket.SocketRequestParser.parseBody(hxReq, input);
						} catch (e:Dynamic) {
							// If abort() was called or other parse error, we log it
							HybridLogger.warn('[HxWellAdapter] Body parse error: ' + e);
						}
						hx.well.http.RequestStatic.set(null);
					}
				}
				
				adapter.pushRequest({hxRequest: hxReq, socket: socket});
			} catch (e:Dynamic) {
				HybridLogger.error('[HxWellAdapter] Background parse error: ' + e);
				try {
					socket.close();
				} catch (_) {}
			}
		});
	}
}
