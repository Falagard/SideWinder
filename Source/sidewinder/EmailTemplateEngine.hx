package sidewinder;

import haxe.Template;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

class EmailTemplateEngine {
	public var templatesDir:String;

	public function new(?templatesDir:String) {
		this.templatesDir = templatesDir != null ? templatesDir : "templates/email";
	}

	public function render(templateName:String, data:Dynamic):String {
		var safeName = sanitizeTemplateName(templateName);
		if (safeName == null) {
			throw 'Invalid template name: $templateName';
		}

		var path = templatesDir + "/" + safeName + ".txt";
		if (!FileSystem.exists(path)) {
			throw 'Template not found: $path';
		}

		var source = File.getContent(path);
		var template = new Template(source);
		return template.execute(data != null ? data : {});
	}

	public static function coerceData(data:Dynamic):Dynamic {
		if (data == null) {
			return {};
		}

		if (Std.isOfType(data, String)) {
			try {
				return Json.parse(cast data);
			} catch (e:Dynamic) {
				return {raw: data};
			}
		}

		return data;
	}

	private static function sanitizeTemplateName(name:String):Null<String> {
		if (name == null || name == "") {
			return null;
		}
		var re = ~/^[A-Za-z0-9_-]+$/;
		return re.match(name) ? name : null;
	}
}
