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
