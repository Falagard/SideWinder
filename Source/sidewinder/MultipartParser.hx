package sidewinder;

import haxe.ds.StringMap;
import sidewinder.Router;

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
				if (headerEndPos == -1)
					continue;
			}

			var headerSection = part.substr(0, headerEndPos);
			var bodySection = part.substr(headerEndPos + 4);

			// Remove trailing \r\n
			if (StringTools.endsWith(bodySection, "\r\n")) {
				bodySection = bodySection.substr(0, bodySection.length - 2);
			}

			// Parse Content-Disposition header
			var disposition = extractHeader(headerSection, "Content-Disposition");
			if (disposition == null)
				continue;

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
		if (contentType == null)
			return null;

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
