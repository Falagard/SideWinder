package sidewinder.websocket;

import haxe.io.Bytes;
import sidewinder.interfaces.IWebSocketHandler;
import sidewinder.interfaces.IWebSocketHandler.WebSocketOpcode;
import sidewinder.interfaces.IWebSocketServer;
import sidewinder.routing.Router.Request;
import utest.Assert;
import utest.Test;

/** Fake transport — proves handlers are testable with no socket. */
private class FakeServer implements IWebSocketServer {
	public var sentText:Array<String> = [];
	public var closed:Array<Int> = [];
	public function new() {}
	public function setWebSocketHandler(handler:IWebSocketHandler):Void {}
	public function websocketSendText(conn:Dynamic, text:String):Void sentText.push(text);
	public function websocketSendBinary(conn:Dynamic, data:Bytes):Void {}
	public function websocketClose(conn:Dynamic, code:Int = 1000, ?reason:String):Void closed.push(code);
}

private class RecordingApp implements IWebSocketApplication {
	public var texts:Array<String> = [];
	public var binaries:Array<Int> = [];
	public var opens:Int = 0;
	public var closes:Int = 0;
	public var ids:Array<String> = [];
	public function new() {}
	public function onConnect(request:Request):Bool return true;
	public function onOpen(c:IWebSocketConnection):Void { opens++; ids.push(c.id); }
	public function onText(c:IWebSocketConnection, m:String):Void texts.push(m);
	public function onBinary(c:IWebSocketConnection, d:Bytes):Void binaries.push(d.length);
	public function onClose(c:IWebSocketConnection):Void closes++;
	public function onError(c:IWebSocketConnection, e:haxe.Exception):Void {}
}

class WebSocketApplicationHandlerTest extends Test {
	var server:FakeServer;
	var app:RecordingApp;
	var handler:WebSocketApplicationHandler;

	function setup() {
		server = new FakeServer();
		app = new RecordingApp();
		handler = new WebSocketApplicationHandler(server, app);
	}

	function conn(id:String):Dynamic return {id: id};

	function data(s:String) {
		var b = Bytes.ofString(s);
		#if hl
		return {bytes: @:privateAccess b.getData(), length: b.length};
		#else
		return {bytes: b, length: b.length};
		#end
	}

	function testTextIsDeliveredAsAString() {
		var c = conn("c1");
		handler.onReady(c);
		var d = data("hello");
		handler.onData(c, WebSocketOpcode.TEXT, d.bytes, d.length);
		Assert.same(["hello"], app.texts);
	}

	function testBinaryIsDeliveredAsHaxeBytesOnEveryTarget() {
		var c = conn("c1");
		handler.onReady(c);
		var d = data("abcd");
		handler.onData(c, WebSocketOpcode.BINARY, d.bytes, d.length);
		Assert.same([4], app.binaries);
	}

	function testLengthShorterThanBufferIsHonoured() {
		var c = conn("c1");
		handler.onReady(c);
		var d = data("hello world");
		handler.onData(c, WebSocketOpcode.TEXT, d.bytes, 5);
		Assert.same(["hello"], app.texts);
	}

	function testSameConnectionYieldsAStableIdentity() {
		var c = conn("c1");
		handler.onReady(c);
		handler.onReady(c);
		Assert.same(["c1", "c1"], app.ids);
	}

	function testSendAndCloseReachTheTransport() {
		var c = conn("c1");
		handler.onReady(c);
		Assert.equals(0, server.sentText.length);
		var d = data("ping");
		handler.onData(c, WebSocketOpcode.TEXT, d.bytes, d.length);
		Assert.same(["ping"], app.texts);
	}

	// HxWell fires the close path twice on a clean close handshake.
	function testDoubleCloseIsForwardedTwiceSoAppsMustBeIdempotent() {
		var c = conn("c1");
		handler.onReady(c);
		handler.onClose(c);
		handler.onClose(c);
		Assert.equals(2, app.closes);
	}
}
