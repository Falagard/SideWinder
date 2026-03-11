package hx.well.config;

class HttpConfig implements IConfig {
	public function new() {}

	public var max_content_length:Int = 10 * 1024 * 1024; // 10MB
	public var max_buffer:Int = 1048576; // 1MB
	public var max_path_length:Int = 256;
	public var public_path:String = "static";
	public var cache_path:String = "cache";
}
