package;

import hx.injection.Service;

interface ICacheService extends Service {
    public function set(key:String, value:Dynamic, ?ttlMs:Int):Void;
    public function get(key:String):Null<Dynamic>;
    public function getOrCompute(key:String, computeFn:Void->Dynamic, ?ttlMs:Int):Dynamic;
    public function sweepExpired():Void;
}
