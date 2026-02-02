package sidewinder;

import haxe.ds.StringMap;
import snake.http.*;

typedef Request = {
	var method:String;
	var path:String;
	var headers:Map<String, String>;
	var query:Map<String, String>;
	var params:Map<String, String>;
	var body:String;
	var jsonBody:Dynamic;
	var formBody:StringMap<String>;
	var cookies:StringMap<String>;
	var files:Array<UploadedFile>;
	var ?ip:String;
};

typedef UploadedFile = {
	var fieldName:String;      // Form field name
	var fileName:String;       // Original filename
	var filePath:String;       // Saved path on server
	var contentType:String;    // MIME type
	var size:Int;              // File size in bytes
	@:optional var authContext:AuthContext;
};

typedef AuthContext = {
	var authenticated:Bool;
	var userId:Null<Int>;
	var session:Null<Dynamic>;
	var token:Null<String>;
};

typedef Response = {
	var write:(String) -> Void;
	var setHeader:(String, String) -> Void;
	var sendError:(HTTPStatus) -> Void;
	var sendResponse:(HTTPStatus) -> Void;
	var endHeaders:() -> Void;
	var end:() -> Void;
	var setCookie:(name:String, value:String, ?options:{path:String, domain:String, maxAge:String, httpOnly:Bool, secure:Bool}) -> Void;
};

class Route {
	public var method:String;
	public var pattern:String;
	public var regex:EReg;
	public var paramNames:Array<String>;
	public var handler:Handler;

	public function new(method:String, pattern:String, handler:Handler) {
		this.method = method;
		this.pattern = pattern;
		this.handler = handler;
		var parts = pattern.split("/");
		var reParts = [];
		paramNames = [];
		for (p in parts) {
			if (StringTools.startsWith(p, ":")) {
				paramNames.push(p.substr(1));
				reParts.push("([^/]+)");
			} else {
				reParts.push(EReg.escape(p));
			}
		}
		var patternRe = "^" + reParts.join("/") + "$";
		this.regex = new EReg(patternRe, "");
	}

	public function matches(path:String):Null<Map<String, String>> {
		if (!regex.match(path))
			return null;
		var params = new Map<String, String>();
		for (i in 0...paramNames.length) {
			params.set(paramNames[i], regex.matched(i + 1));
		}
		return params;
	}
}

typedef Middleware = (Request, Response, Void->Void) -> Void;
typedef Handler = Request->Response->Void;

typedef RouteResult = {
	route:Route,
	params:Map<String, String>
}

class Router {
	public var routes:Array<Route> = [];
	public var middleware:Array<Middleware> = [];

	public function new() {}

	public function add(method:String, pattern:String, handler:Handler):Void {
		routes.push(new Route(method, pattern, handler));
	}

	public function use(mw:Middleware):Void {
		middleware.push(mw);
	}

	public function find(method:String, path:String):Null<RouteResult> {
		for (route in routes) {
			if (route.method == method) {
				var params = route.matches(path);
				if (params != null) {
					return {route: route, params: params};
				}
			}
		}
		return null;
	}

	public function handle(req:Request, res:Response, route:Route) {
		return runMiddleware(0, req, res, route);
	}

	function runMiddleware(index:Int, req:Request, res:Response, route:Route) {
	  if (index < middleware.length) {
			var mw = middleware[index];
			return mw(req, res, () -> runMiddleware(index + 1, req, res, route));
		} else {
			return route.handler(req, res);
		}
	}
}

/**
 * Utility class for parsing multipart/form-data file uploads
 */
class MultipartParser {
	private static var uploadDir:String = "uploads";
	
	public static function setUploadDirectory(dir:String):Void {
		uploadDir = dir;
		if (!sys.FileSystem.exists(uploadDir)) {
			sys.FileSystem.createDirectory(uploadDir);
		}
	}
	
	public static function parseMultipart(body:String, contentType:String):{
		files:Array<UploadedFile>,
		fields:StringMap<String>
	} {
		var files:Array<UploadedFile> = [];
		var fields = new StringMap<String>();
		
		// Extract boundary from content-type header
		var boundary = extractBoundary(contentType);
		if (boundary == null) {
			return {files: files, fields: fields};
		}
		
		// Split by boundary
		var parts = body.split("--" + boundary);
		
		for (part in parts) {
			if (part.length < 10 || StringTools.trim(part) == "" || StringTools.trim(part) == "--") {
				continue;
			}
			
			// Split headers from body
			var headerEndPos = part.indexOf("\r\n\r\n");
			if (headerEndPos == -1) {
				headerEndPos = part.indexOf("\n\n");
				if (headerEndPos == -1) continue;
			}
			
			var headerSection = part.substr(0, headerEndPos);
			var bodySection = part.substr(headerEndPos + 4);
			
			// Remove trailing \r\n
			if (StringTools.endsWith(bodySection, "\r\n")) {
				bodySection = bodySection.substr(0, bodySection.length - 2);
			}
			
			// Parse Content-Disposition header
			var disposition = extractHeader(headerSection, "Content-Disposition");
			if (disposition == null) continue;
			
			var fieldName = extractQuotedValue(disposition, "name");
			var fileName = extractQuotedValue(disposition, "filename");
			
			if (fileName != null && fileName != "") {
				// File upload
				var contentTypeHeader = extractHeader(headerSection, "Content-Type");
				var mimeType = contentTypeHeader != null ? StringTools.trim(contentTypeHeader) : "application/octet-stream";
				
				// Generate unique filename
				var timestamp = Std.string(Date.now().getTime());
				var random = Std.string(Math.floor(Math.random() * 10000));
				var ext = haxe.io.Path.extension(fileName);
				var safeName = timestamp + "_" + random + (ext != "" ? "." + ext : "");
				var savePath = haxe.io.Path.join([uploadDir, safeName]);
				
				// Save file
				try {
					sys.io.File.saveContent(savePath, bodySection);
					
					files.push({
						fieldName: fieldName,
						fileName: fileName,
						filePath: savePath,
						contentType: mimeType,
						size: bodySection.length
					});
					
					HybridLogger.info('[MultipartParser] Saved file: $fileName -> $savePath (${bodySection.length} bytes)');
				} catch (e:Dynamic) {
					HybridLogger.error('[MultipartParser] Failed to save file $fileName: $e');
				}
			} else {
				// Regular form field
				if (fieldName != null) {
					fields.set(fieldName, bodySection);
				}
			}
		}
		
		return {files: files, fields: fields};
	}
	
	private static function extractBoundary(contentType:String):Null<String> {
		if (contentType == null) return null;
		
		var boundaryPattern = ~/boundary=([^;\s]+)/;
		if (boundaryPattern.match(contentType)) {
			var boundary = boundaryPattern.matched(1);
			// Remove quotes if present
			if (StringTools.startsWith(boundary, '"') && StringTools.endsWith(boundary, '"')) {
				boundary = boundary.substr(1, boundary.length - 2);
			}
			return boundary;
		}
		return null;
	}
	
	private static function extractHeader(headerSection:String, headerName:String):Null<String> {
		var lines = headerSection.split("\n");
		for (line in lines) {
			var trimmed = StringTools.trim(line).toLowerCase();
			if (StringTools.startsWith(trimmed, headerName.toLowerCase() + ":")) {
				return StringTools.trim(line.substr(headerName.length + 1));
			}
		}
		return null;
	}
	
	private static function extractQuotedValue(str:String, key:String):Null<String> {
		var pattern = new EReg(key + '="([^"]+)"', "i");
		if (pattern.match(str)) {
			return pattern.matched(1);
		}
		return null;
	}
}
