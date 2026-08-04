package sidewinder.client;

/**
 * Structured client-side view of a non-2xx HTTP response, replacing the
 * bare `Dynamic` that used to reach every AsyncClient onFailure/onError
 * callback. `code` is a best-effort extraction, not a new wire contract:
 * if the body's "error"/"message" field looks like "SOME_CODE: rest of
 * text" (an all-uppercase/underscore prefix before the first ": "), that
 * prefix becomes `code` and the remainder becomes `message`. Otherwise
 * `code` is null and `message` is the full field value.
 *
 * CRITICAL: this is `abstract ClientErrorInfo(String)`, NOT a typedef/
 * anonymous struct. Many existing PlatformUI call sites declare their
 * onFailure callback as `function(err:String) {...}` -- a statically
 * String-typed closure parameter. `AutoClientAsync`'s generated `onFailure`
 * is `Dynamic->Void`, so Haxe's compile-time unification happily lets a
 * `String`-typed closure bind there -- but on HL, the closure's OWN
 * declared parameter type is enforced at the actual call boundary, at
 * runtime, regardless of what the caller side declared. Handing such a
 * closure an anonymous struct (the original typedef design) crashes with
 * `Can't cast virtual<...> to String` the instant a real non-2xx response
 * reaches it -- this is the exact "Can't cast X to Y" HL gotcha documented
 * in root CLAUDE.md. Since a Haxe abstract has NO wrapper object at
 * runtime -- the value literally IS its underlying type -- a
 * `ClientErrorInfo` value passed into a `function(err:String)` closure IS,
 * at the HL ABI level, a plain String (a JSON-encoded blob), so it passes
 * that runtime type check with zero crash risk. Existing
 * `Std.string(err).indexOf("403")`-style substring matching keeps working
 * unchanged too, since the JSON text contains the status code digits.
 * New structured callers get typed `.status`/`.code`/`.message` access via
 * the properties below (each re-parses the JSON on access -- this type is
 * for occasional inspection, not a hot path).
 */
abstract ClientErrorInfo(String) {
    public inline function new(raw:String) {
        this = raw;
    }

    public static function build(status:Int, code:Null<String>, message:String):ClientErrorInfo {
        return new ClientErrorInfo(haxe.Json.stringify({status: status, code: code, message: message}));
    }

    public var status(get, never):Int;
    function get_status():Int {
        try {
            var v = Reflect.field(haxe.Json.parse(this), "status");
            return v == null ? 0 : v;
        } catch (e:Dynamic) {
            return 0;
        }
    }

    public var code(get, never):Null<String>;
    function get_code():Null<String> {
        try {
            return Reflect.field(haxe.Json.parse(this), "code");
        } catch (e:Dynamic) {
            return null;
        }
    }

    public var message(get, never):String;
    function get_message():String {
        try {
            var v = Reflect.field(haxe.Json.parse(this), "message");
            return v == null ? this : v;
        } catch (e:Dynamic) {
            return this;
        }
    }

    @:to public inline function toString():String {
        return this;
    }
}
