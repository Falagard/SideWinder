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

import hx.well.websocket.WebSocketSession;
import hx.well.websocket.AbstractWebSocketHandler as HxAbstractWebSocketHandler;
import haxe.io.Bytes;
import haxe.Exception;

class HxWellWebSocketBridge extends HxAbstractWebSocketHandler {
	private var adapter:HxWellAdapter;

	public function new(adapter:HxWellAdapter) {
		super();
		this.adapter = adapter;
	}

	public function onOpen(session:WebSocketSession):Void {
		adapter.pushWebSocketEvent({type: Open, session: session});
	}

	public function onMessage(session:WebSocketSession, message:String):Void {
		adapter.pushWebSocketEvent({type: Message, session: session, data: Bytes.ofString(message)});
	}

	public function onBinary(session:WebSocketSession, data:Bytes):Void {
		adapter.pushWebSocketEvent({type: Binary, session: session, data: data});
	}

	public function onClose(session:WebSocketSession, code:Int, reason:String):Void {
		adapter.pushWebSocketEvent({type: Close, session: session});
	}

	public function onError(session:WebSocketSession, error:Exception):Void {
		HybridLogger.error('[HxWellAdapter] WebSocket error for session ${session.id}: ' + error);
	}
}
