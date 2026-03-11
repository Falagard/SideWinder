package hx.well.config;

class ConfigData {
	public static var httpconfig:HttpConfig = new HttpConfig();
	public static var middlewareconfig:MiddlewareConfig = new MiddlewareConfig();
	public static var databaseconfig:DatabaseConfig = new DatabaseConfig();
	public static var providerconfig:ProviderConfig = new ProviderConfig();
	public static var instanceconfig:InstanceConfig = new InstanceConfig();
	public static var sessionconfig:SessionConfig = new SessionConfig();

	public static function init() {}

	public function new() {}
}
