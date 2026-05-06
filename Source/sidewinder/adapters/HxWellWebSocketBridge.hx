package sidewinder.adapters;

import sidewinder.logging.HybridLogger;

import hx.well.websocket.WebSocketSession;
import hx.well.websocket.AbstractWebSocketHandler as HxAbstractWebSocketHandler;
import haxe.io.Bytes;
import haxe.Exception;

class HxWellWebSocketBridge extends HxAbstractWebSocketHandler {
	private var adapter:HxWellAdapter;
	private var initialRequest:hx.well.http.Request;

	public function new(adapter:HxWellAdapter, initialRequest:hx.well.http.Request) {
		super();
		this.adapter = adapter;
		this.initialRequest = initialRequest;
	}

	public function onOpen(session:WebSocketSession):Void {
		// Convert hxwell request to SideWinder request for context
		var swReq = @:privateAccess adapter.convertRequest(initialRequest, null);
		adapter.pushWebSocketEvent({type: Connect(session, swReq), session: session});
		adapter.pushWebSocketEvent({type: Open(session), session: session});
	}

	public function onMessage(session:WebSocketSession, message:String):Void {
		adapter.pushWebSocketEvent({type: Message(session, message), session: session, data: Bytes.ofString(message)});
	}

	public function onBinary(session:WebSocketSession, data:Bytes):Void {
		adapter.pushWebSocketEvent({type: Binary(session, data), session: session, data: data});
	}

	public function onClose(session:WebSocketSession, code:Int, reason:String):Void {
		adapter.pushWebSocketEvent({type: Close(session), session: session});
	}

	public function onError(session:WebSocketSession, error:Exception):Void {
		HybridLogger.error('[HxWellAdapter] WebSocket error for session ${session.id}: ' + error);
	}
}
