package sidewinder.core;

import hx.injection.ServiceCollection;
import hx.injection.ServiceProvider;
#if (sys && !html5)
import sys.thread.Thread;
#end
import haxe.ds.ObjectMap;

class DI {
#if (sys && !html5)
	private static var _providers:ObjectMap<Dynamic, ServiceProvider> = new ObjectMap();
#end
	private static var _globalProvider:ServiceProvider;
#if (sys && !html5)
	private static var _mutex:sys.thread.Mutex = new sys.thread.Mutex();
#end

	public static function init(configure:(ServiceCollection) -> Void):Void {
		#if (sys && !html5)
		var thread = Thread.current();
		_mutex.acquire();
		var provider = _providers.get(thread);
		if (provider != null) {
			_mutex.release();
			return;
		}
		#else
		if (_globalProvider != null) return;
		#end
			
		var collection = new ServiceCollection();
		configure(collection);
		var provider = collection.createProvider();
		
		#if (sys && !html5)
		_providers.set(thread, provider);
		#end
		
		// Set global provider if not set (for non-threaded or main thread access)
		if (_globalProvider == null) {
			_globalProvider = provider;
		}
		
		#if (sys && !html5)
		_mutex.release();
		#end
	}

	public static function provider():ServiceProvider {
		#if (sys && !html5)
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
		#else
		if (_globalProvider == null) throw 'DI not initialized. Call DI.init() first.';
		return _globalProvider;
		#end
	}

	public static function get<S:hx.injection.Service>(service:Class<S>, ?binding:Null<Class<S>>):S {
		return provider().getService(service, binding);
	}
}
