package hx.well.config;

import hx.well.middleware.AbstractMiddleware;
import hx.well.facades.Config;

class MiddlewareConfig implements IConfig {
	public function new() {}

	public function get():Array<Class<AbstractMiddleware>> {
		return [];
	}
}
