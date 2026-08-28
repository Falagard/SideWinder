package sidewinder.http;

/**
 * Creates the per-request scope. Supplied by the host application; the
 * transport never constructs a container itself
 * (SIDEWINDER-CORE-DECOUPLING-S1 Tasks E + G).
 */
interface IRequestScopeFactory {
	function create(requestId:String):IRequestScope;
}
