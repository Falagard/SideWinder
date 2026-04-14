package sidewinder.data;

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


import haxe.ds.StringMap;
import snake.http.*;


/**
 * Helper class to capture Router response for synchronous return.
 */
class BufferedResponse {
	public var statusCode:Int = 200;
	public var headers:Map<String, String> = new Map();
	public var body:StringBuf = new StringBuf();

	// Function fields to match Router.Response typedef
	public var write:(String) -> Void;
	public var writeBytes:(haxe.io.Bytes) -> Void;
	public var setHeader:(String, String) -> Void;
	public var sendError:(snake.http.HTTPStatus) -> Void;
	public var sendResponse:(snake.http.HTTPStatus) -> Void;
	public var endHeaders:() -> Void;
	public var end:() -> Void;
	public var setCookie:(name:String, value:String, ?options:{
		path:String,
		domain:String,
		maxAge:String,
		httpOnly:Bool,
		secure:Bool
	}) -> Void;

	public function new() {
		// Initialize function fields with closures capturing 'this'

		write = function(s:String):Void {
			body.add(s);
		};
		
		writeBytes = function(b:haxe.io.Bytes):Void {
			body.add(b.toString());
		};

		setHeader = function(k:String, v:String):Void {
			headers.set(k, v);
		};

		sendError = function(code:snake.http.HTTPStatus):Void {
			statusCode = code.code;
		};

		sendResponse = function(code:snake.http.HTTPStatus):Void {
			statusCode = code.code;
		};

		endHeaders = function():Void {};

		end = function():Void {};

		setCookie = function(name:String, value:String, ?options:{
			path:String,
			domain:String,
			maxAge:String,
			httpOnly:Bool,
			secure:Bool
		}):Void {
			var cookie = name + "=" + value;
			if (options != null) {
				if (options.path != null)
					cookie += "; Path=" + options.path;
				if (options.domain != null)
					cookie += "; Domain=" + options.domain;
				if (options.maxAge != null)
					cookie += "; Max-Age=" + options.maxAge;
				if (options.httpOnly)
					cookie += "; HttpOnly";
				if (options.secure)
					cookie += "; Secure";
			}
			headers.set("Set-Cookie", cookie);
		};
	}

	public function toSimpleResponse():CivetWebAdapter.SimpleResponse {
		var bodyStr = body.toString();
		var contentType = headers.exists("Content-Type") ? headers.get("Content-Type") : "text/html";
		return {
			statusCode: statusCode,
			contentType: contentType,
			body: bodyStr,
			headers: headers
		};
	}
}



