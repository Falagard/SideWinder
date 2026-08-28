package sidewinder.http;

// SIDEWINDER-CORE-DECOUPLING-S1 (Tasks E + G).
//
// Generic per-request state. This is the abstraction that replaces the
// transport's hard-coded knowledge of `app.services.ProjectContext`.
//
// The transport creates one of these per request, hands it to the host
// application's `onScopeSetup` hook, and disposes it when the request ends.
// It knows nothing about what the application puts inside.
//
// The full Server's implementation (see
// `sidewinder.integration.injection.DiRequestScopeFactory`) backs this with an
// hx-injection scope and attaches a `ProjectContext`. A lightweight
// application gets `MapRequestScope`, which needs no DI container at all.
interface IRequestScope {
	/** Correlation id for this request. */
	var requestId(default, null):String;

	function setAttribute(key:String, value:Dynamic):Void;
	function getAttribute(key:String):Null<Dynamic>;

	/**
	 * The underlying container-specific scope object, or null when there is no
	 * container. Host applications that know their own factory may cast this;
	 * the transport never inspects it.
	 */
	function unwrap():Null<Dynamic>;

	/** Release any resources. Called exactly once, on the request's exit path. */
	function dispose():Void;
}
