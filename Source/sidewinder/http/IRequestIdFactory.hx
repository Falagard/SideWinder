package sidewinder.http;

// SIDEWINDER-CORE-DECOUPLING-S1 (Task F).
//
// Request IDs are useful but must not be a hard dependency of the HTTP
// transport. Previously `HxWellAdapter` selected between
// `app.util.RequestId.generate()` and an inline fallback with
// `#if haxestack_platform_server` -- i.e. the transport had compile-time
// knowledge of one specific host application.
//
// Now the transport takes an `IRequestIdFactory`. The Server supplies its own
// (wrapping `app.util.RequestId`); a lightweight application supplies nothing
// and gets `SequentialRequestIdFactory`, which needs no UUID library.
interface IRequestIdFactory {
	function generate():String;
}
