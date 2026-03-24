package sidewinder.core;

import hx.injection.ServiceCollection;
import hx.injection.ServiceProvider;
import sys.thread.Thread;
import haxe.ds.ObjectMap;

class DI {
	private static var _providers:ObjectMap<Dynamic, ServiceProvider> = new ObjectMap();
	private static var _globalProvider:ServiceProvider;
	private static var _mutex:sys.thread.Mutex = new sys.thread.Mutex();

	public static function init(configure:(ServiceCollection) -> Void):Void {
		var thread = Thread.current();
		_mutex.acquire();
		var provider = _providers.get(thread);
		if (provider != null) {
			_mutex.release();
			return;
		}
			
		var collection = new ServiceCollection();
		configure(collection);
		provider = collection.createProvider();
		_providers.set(thread, provider);
		
		// Set global provider if not set (for non-threaded or main thread access)
		if (_globalProvider == null) {
			_globalProvider = provider;
		}
		_mutex.release();
	}

	public static function provider():ServiceProvider {
		var thread = Thread.current();
		_mutex.acquire();
		var provider = _providers.get(thread);
		_mutex.release();
		
		if (provider == null) {
			// Fallback to global provider if thread-local is not initialized
			if (_globalProvider != null) return _globalProvider;
			throw 'DI not initialized. Call DI.init() first.';
		}
		return provider;
	}

	public static function get<S:hx.injection.Service>(service:Class<S>, ?binding:Null<Class<S>>):S {
		return provider().getService(service, binding);
	}
}
