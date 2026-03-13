package sidewinder.adapters;

import sys.net.Socket;
import haxe.io.Bytes;
import hx.well.websocket.WebSocketSession;

typedef QueuedRequest = {
	var socket:Socket;
	var hxRequest:hx.well.http.Request;
}

enum WebSocketEventData {
	Open(session:WebSocketSession);
	Message(session:WebSocketSession, text:String);
	Binary(session:WebSocketSession, data:Bytes);
	Close(session:WebSocketSession);
}

typedef WebSocketEvent = {
	var type:WebSocketEventData;
	var session:WebSocketSession;
	@:optional var data:Bytes;
}
