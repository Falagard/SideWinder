package;

import hx.injection.ServiceCollection;
import hx.injection.ServiceProvider;

/**
 * Global access point for the application's ServiceProvider.
 * Call DI.init() once at startup, then DI.get() to resolve services.
 */
class DI {
    private static var _provider:ServiceProvider;

    public static function init(configure:(ServiceCollection)->Void):Void {
        if (_provider != null) return; // already initialized
        var collection = new ServiceCollection();
        configure(collection);
        _provider = collection.createProvider();
    }

    public static inline function provider():ServiceProvider {
        if (_provider == null) throw 'DI not initialized. Call DI.init() first.';
        return _provider;
    }

    public static inline function get<S:hx.injection.Service>(service:Class<S>, ?binding:Null<Class<S>>):S {
        return provider().getService(service, binding);
    }
}
