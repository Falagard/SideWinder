package sidewinder.integration.injection;

import sidewinder.http.IRequestScope;
import sidewinder.http.IRequestScopeFactory;

/**
 * `IRequestScopeFactory` backed by hx-injection. Applications that use DI wire
 * this into `HxWellAdapter`; applications that do not, do not reference this
 * class and never link hx-injection through the HTTP path
 * (SIDEWINDER-CORE-DECOUPLING-S1 Task G).
 */
class DiRequestScopeFactory implements IRequestScopeFactory {
	public function new() {}

	public function create(requestId:String):IRequestScope {
		return new DiRequestScope(requestId);
	}
}
