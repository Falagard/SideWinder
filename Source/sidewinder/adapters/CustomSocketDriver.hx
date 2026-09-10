package sidewinder.adapters;

import sidewinder.logging.HybridLogger;
import sidewinder.adapters.HxWellAdapterTypes;

import hx.well.http.driver.socket.SocketDriver;
import hx.well.http.driver.socket.SocketRequestParser;
import hx.well.http.driver.socket.SocketInput;
import hx.well.http.driver.socket.SocketWebSocketHandler;
import hx.well.http.RequestStatic;
import sys.net.Socket;
import haxe.Http;
import sidewinder.http.IHttpServerOptions;
import sidewinder.http.WebSocketAdmissionPolicy;

@:access(hx.well.http.driver.socket.SocketDriver)
class CustomSocketDriver extends SocketDriver {
	private var adapter:HxWellAdapter;

	// SIDEWINDER-CORE-DECOUPLING-S1 (Task C): transport limits arrive by
	// constructor injection instead of `DI.get(core.IServerConfig)` on every
	// request. That removed this class's dependency on both the
	// HaxeStackPlatform Server application AND on hx-injection.
	private var options:IHttpServerOptions;

	// Task K: refuses WebSocket upgrades past the configured ceiling so
	// long-lived sockets can never consume the worker pool's HTTP headroom.
	private var wsAdmission:WebSocketAdmissionPolicy;

	public function new(config, adapter, options:IHttpServerOptions, wsAdmission:WebSocketAdmissionPolicy) {
		super(config);
		this.adapter = adapter;
		this.options = options;
		this.wsAdmission = wsAdmission;
	}

	override public function process(socket:Socket):Void {
		// Run in background threadpool provided by SocketDriver
		@:privateAccess executor.submit(() -> {
			try {
				// Set TCP_NODELAY (FastSend) on client socket
				socket.setFastSend(true);
				
				var peer = null;
				try {
					peer = socket.peer();
				} catch (e:Dynamic) {
					// Connection already reset or closed by peer
					HybridLogger.debug('[HxWellAdapter] Connection reset by peer before parsing');
					try { socket.close(); } catch (_) {}
					return;
				}

				var hxReq = hx.well.http.driver.socket.SocketRequestParser.parseFromSocket(socket);

				// Enforce header size limit
				var totalHeaderSize = 0;
				for (k in hxReq.headers.keys()) {
					totalHeaderSize += k.length + hxReq.headers.get(k).length + 4; // +4 for ": " and "\r\n"
				}
				if (totalHeaderSize > options.maxHeaderSize) {
					HybridLogger.warn('[HxWellAdapter] Headers too large: $totalHeaderSize > ${options.maxHeaderSize}');
					// We can't easily send a 431 Request Header Fields Too Large here because we already parsed part of the request
					// but we can at least abort.
					try {
						socket.output.writeString("HTTP/1.1 431 Request Header Fields Too Large\r\nConnection: close\r\n\r\n");
						socket.output.flush();
						socket.close();
					} catch (_) {}
					return;
				}

				// Check for WebSocket upgrade
				var upgrade = hxReq.header("Upgrade");
				if (upgrade != null && upgrade.toLowerCase() == "websocket") {
					// AUTHENTICATION BOUNDARY. The application's own veto --
					// IWebSocketHandler.onConnect -- runs HERE, synchronously, on the request
					// thread, BEFORE any 101 is written and before any WebSocketSession exists.
					//
					// It used to run far later: SocketWebSocketHandler.upgrade() writes and
					// flushes 101 first, then constructs the session and calls onOpen, which only
					// ENQUEUES Connect/Open for HxWellAdapter's WebSocket event thread. onConnect
					// was evaluated there, after the upgrade had already been granted, so a
					// rejected client held a live upgraded connection and the only remedy left was
					// session.close() -- whose observability to the peer depends on OS
					// socket-close timing rather than on the protocol (a HaxeStackPlatform Linux
					// integration test failed 4/4 runs on exactly that). It also left the queued
					// Open event free to dispatch onReady() for a connection that had just been
					// refused, because nothing marks a session rejected.
					//
					// Refusing before the upgrade makes that class structurally impossible: no
					// 101, no session, no onOpen, no Connect/Open events -- therefore no onReady
					// and no subscription can exist for a rejected client.
					//
					// SideWinder learns nothing application-specific here: the decision is
					// entirely the handler's, exactly as it already was. This mirrors the capacity
					// refusal immediately below, which has always written its status pre-upgrade.
					//
					// 403 rather than 401: onConnect returns a bare Bool and cannot say WHY it
					// refused -- the same `false` covers a bad credential and an application-level
					// connection cap. 401 asserts specifically that authentication is required and
					// is meant to carry a WWW-Authenticate challenge this boundary cannot
					// construct. 403 ("understood, refusing to authorize") is the honest mapping.
					var wsHandler = @:privateAccess adapter.websocketHandler;
					if (wsHandler != null) {
						var admitted = false;
						try {
							admitted = wsHandler.onConnect(@:privateAccess adapter.convertRequest(hxReq, null));
						} catch (e:Dynamic) {
							// Fail CLOSED. A veto that could not be evaluated is not consent.
							HybridLogger.error('[HxWellAdapter] WebSocket onConnect threw; refusing upgrade: ' + e);
							admitted = false;
						}
						if (!admitted) {
							HybridLogger.warn('[HxWellAdapter] WebSocket upgrade refused by handler (403)');
							try {
								socket.output.writeString("HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
								socket.output.flush();
								socket.close();
							} catch (_) {}
							return;
						}
					}

					// Task K: a WebSocket occupies this worker until it closes.
					// Refuse rather than let sockets exhaust the pool -- at
					// pool exhaustion the server stops answering HTTP *and*
					// stops accepting connections.
					if (!wsAdmission.tryAcquire()) {
						HybridLogger.warn('[HxWellAdapter] WebSocket upgrade refused: at capacity ('
							+ wsAdmission.getLimit() + ' concurrent connections)');
						try {
							socket.output.writeString("HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
							socket.output.flush();
							socket.close();
						} catch (_) {}
						return;
					}
					var bridge = new HxWellWebSocketBridge(adapter, hxReq);
					// This blocks the background thread and handles the message loop
					try {
						hx.well.http.driver.socket.SocketWebSocketHandler.upgrade(socket, hxReq, bridge);
					} catch (e:Dynamic) {
						HybridLogger.error('[HxWellAdapter] WebSocket session error: ' + e);
					}
					// Haxe has no `finally`; release on both paths. The policy
					// itself floors at zero, and the bridge guards against
					// HxWell's double-close, so this is safe to reach once per
					// accepted upgrade.
					wsAdmission.release();
					return;
				}
				
				// Handle body parsing if Content-Length is present
                var headersStr = "";
                for (k in hxReq.headers.keys()) headersStr += k + ": " + hxReq.headers.get(k) + ", ";
                HybridLogger.info('[HxWellAdapter] Request Headers: ' + headersStr);
				var contentLen = hxReq.header("Content-Length");
				
				if (contentLen != null) {
					var len = Std.parseInt(contentLen);
					if (len > options.maxRequestBodySize) {
						HybridLogger.warn('[HxWellAdapter] Content-Length too large: $len > ${options.maxRequestBodySize}');
						try {
							socket.output.writeString("HTTP/1.1 413 Payload Too Large\r\nConnection: close\r\n\r\n");
							socket.output.flush();
							socket.close();
						} catch (_) {}
						return;
					}
					if (len > 0) {
						var input = new hx.well.http.driver.socket.SocketInput(socket);
						input.length = len;
						
						// Set static context so hxwell internal parsers can find the request
						hx.well.http.RequestStatic.set(hxReq);
						try {
                            HybridLogger.info('[HxWellAdapter] Parsing body: len=' + len + ' type=' + hxReq.header("Content-Type"));
							hx.well.http.driver.socket.SocketRequestParser.parseBody(hxReq, input);
                            
                            // FALLBACK: If bodyBytes is still null after parseBody, read it manually
                            if (hxReq.bodyBytes == null) {
                                HybridLogger.info('[HxWellAdapter] parseBody did not set bodyBytes, reading manually...');
                                hxReq.bodyBytes = input.read(len);
                                HybridLogger.info('[HxWellAdapter] Manually read bodyBytes: ' + (hxReq.bodyBytes != null ? Std.string(hxReq.bodyBytes.length) : "NULL"));
                            } else {
                                HybridLogger.info('[HxWellAdapter] parseBody set bodyBytes: ' + Std.string(hxReq.bodyBytes.length));
                            }
						} catch (e:Dynamic) {
							// If abort() was called or other parse error, we log it
							if (Std.isOfType(e, haxe.io.Eof) || Std.string(e) == "Eof") {
								HybridLogger.debug('[HxWellAdapter] Body parse Eof (client disconnected)');
							} else {
								HybridLogger.warn('[HxWellAdapter] Body parse error: ' + e);
							}
						}
						hx.well.http.RequestStatic.set(null);
					}
				}
				
				adapter.pushRequest({hxRequest: hxReq, socket: socket});
			} catch (e:Dynamic) {
				if (Std.isOfType(e, haxe.io.Eof) || Std.string(e) == "Eof") {
					HybridLogger.debug('[HxWellAdapter] Background parse Eof (connection closed before request data sent)');
				} else {
					HybridLogger.error('[HxWellAdapter] Background parse error: ' + e + '\n' + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
				}
				try {
					// Attempt to drain and close gracefully
					socket.shutdown(false, true);
					socket.close();
				} catch (_) {}
			}
		});
	}
}
