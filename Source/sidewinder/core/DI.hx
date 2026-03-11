package sidewinder.core;

import sidewinder.routing.Router.UploadedFile;
import sidewinder.routing.Router.Request;
import sidewinder.routing.Router.Response;

import sidewinder.adapters.*;
import sidewinder.services.*;
import sidewinder.interfaces.*;
import sidewinder.routing.*;
import sidewinder.middleware.*;
import sidewinder.websocket.*;
import sidewinder.data.*;
import sidewinder.controllers.*;
import sidewinder.client.*;
import sidewinder.messaging.*;
import sidewinder.logging.*;
import sidewinder.core.*;


import hx.injection.ServiceCollection;
import hx.injection.ServiceProvider;

class DI {
    private static var _provider:ServiceProvider;

    public static function init(configure:(ServiceCollection)->Void):Void {
        if (_provider != null) return;
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




