package hx.well.config;

import hx.well.server.instance.IInstance;

class InstanceConfig implements IConfig {
	public function new() {}

	public function get():Array<IInstance> {
		return [];
	}
}
