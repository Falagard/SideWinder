package sidewinder.client;

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
