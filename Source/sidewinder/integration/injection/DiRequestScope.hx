package sidewinder.integration.injection;

import hx.injection.ServiceProvider;
import sidewinder.core.DI;
import sidewinder.http.IRequestScope;

// SIDEWINDER-CORE-DECOUPLING-S1 (Task G) -- OPTIONAL DI INTEGRATION.
//
// This package is the only place in SideWinder's HTTP path that touches
// hx-injection. `sidewinder.http.*` and `sidewinder.adapters.HxWellAdapter`
// must never import it; they depend on `IRequestScope`/`IRequestScopeFactory`
// only. That is what allows a lightweight hxcpp application to host routes
// with no container linked in.
//
// Behaviour is deliberately identical to what `HxWellAdapter` did inline
// before this refactor: create a scope, install it as the calling thread's
// provider (so AutoRouter-generated handlers resolving via `DI.get(...)` keep
// working unchanged), and tear both down on the request's exit path.
class DiRequestScope implements IRequestScope {
	public var requestId(default, null):String;

	final scope:ServiceProvider;
	final attributes = new Map<String, Dynamic>();
	var disposed:Bool = false;

	public function new(requestId:String) {
		this.requestId = requestId;
		this.scope = DI.createScope();
		DI.setThreadProvider(scope);
	}

	public function setAttribute(key:String, value:Dynamic):Void {
		attributes.set(key, value);
	}

	public function getAttribute(key:String):Null<Dynamic> {
		return attributes.get(key);
	}

	/** The hx-injection `ServiceProvider` for this request. */
	public function unwrap():Null<Dynamic> {
		return scope;
	}

	public function dispose():Void {
		// Idempotent: the transport's cleanup path can be reached from both the
		// normal and the exception route.
		if (disposed)
			return;
		disposed = true;
		attributes.clear();
		DI.resetThreadProvider();
		scope.destroy();
	}
}
