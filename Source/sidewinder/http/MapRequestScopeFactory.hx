package sidewinder.http;

/** Default `IRequestScopeFactory`: produces container-free `MapRequestScope`s. */
class MapRequestScopeFactory implements IRequestScopeFactory {
	public function new() {}

	public function create(requestId:String):IRequestScope {
		return new MapRequestScope(requestId);
	}
}
