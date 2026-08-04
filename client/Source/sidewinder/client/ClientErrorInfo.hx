package sidewinder.client;

/**
 * Structured client-side view of a non-2xx HTTP response, replacing the
 * bare `Dynamic` that used to reach every AsyncClient onFailure/onError
 * callback. `code` is a best-effort extraction, not a new wire contract:
 * if the body's "error"/"message" field looks like "SOME_CODE: rest of
 * text" (an all-uppercase/underscore prefix before the first ": "), that
 * prefix becomes `code` and the remainder becomes `message`. Otherwise
 * `code` is null and `message` is the full field value.
 */
typedef ClientErrorInfo = {
    var status:Int;
    var code:Null<String>;
    var message:String;
}

class ClientErrorInfoParser {
    static var codePattern = ~/^[A-Z_]+$/;

    public static function parse(status:Int, rawBody:String):ClientErrorInfo {
        var message = rawBody == null ? "" : rawBody;
        var code:Null<String> = null;

        if (rawBody != null && rawBody != "") {
            try {
                var parsed:Dynamic = haxe.Json.parse(rawBody);
                var text:String = null;
                if (Reflect.hasField(parsed, "error")) {
                    text = Std.string(Reflect.field(parsed, "error"));
                } else if (Reflect.hasField(parsed, "message")) {
                    text = Std.string(Reflect.field(parsed, "message"));
                }
                if (text != null) {
                    message = text;
                    var sepIndex = text.indexOf(": ");
                    if (sepIndex > 0) {
                        var candidate = text.substr(0, sepIndex);
                        if (codePattern.match(candidate)) {
                            code = candidate;
                            message = text.substr(sepIndex + 2);
                        }
                    }
                }
            } catch (e:Dynamic) {
                // rawBody wasn't JSON (e.g. a plain transport-error string) -- use as-is.
            }
        }

        return {status: status, code: code, message: message};
    }
}
