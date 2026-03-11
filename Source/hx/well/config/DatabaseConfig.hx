package hx.well.config;

import haxe.ds.StringMap;

class DatabaseConfig implements IConfig {
	public function new() {}

	public var connections:StringMap<Dynamic> = new StringMap();
}
