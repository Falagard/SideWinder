package sidewinder;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

/**
 * Macro that inspects an interface annotated with @get/@post/@put/@delete and
 * auto-registers concrete route handlers on a supplied router. For each interface
 * method it:
 *   - Derives HTTP method + path from metadata.
 *   - Extracts primitive args from req.params and complex args from req.jsonBody.
 *   - Instantiates the implementation via implExpr (a factory expression).
 *   - Invokes the method and writes JSON (application/json) for non-void results.
 *   - Supports @requiresAuth metadata to automatically inject userId from session.
 * Notes:
 *   - No try/catch or error normalization is currently added.
 *   - Complex arg resolution is simplistic (falls back to entire req.jsonBody).
 *   - All handlers are synchronous; async/promise return types are not handled.
 */
class AutoRouter {
    public static macro function build(routerExpr:Expr, ifaceExpr:Expr, implExpr:Expr, ?cacheExpr:Expr):Expr {
        var router = routerExpr;
        var routeExprs:Array<Expr> = [];

        // Build expression that extracts an argument value from request (path params, query params, or JSON body).
        function buildArgAccess(argName:String, t:Type, isOpt:Bool):Expr {
            function primitive(kind:Type):Null<String> {
                return switch kind {
                    case TAbstract(a, _):
                        var n = a.get().name;
                        (n == "Int" || n == "Float" || n == "Bool" || n == "String") ? n : null;
                    case _: null;
                };
            }
            var prim = primitive(t);
            if (prim != null) {
                // Check path parameters first, then query parameters
                var base:Expr = macro(req.params.exists($v{argName}) ? req.params.get($v{argName}) : req.query.get($v{argName}));
                if (isOpt)
                    base = macro(req.params.exists($v{argName}) ? req.params.get($v{argName}) : (req.query.exists($v{argName}) ? req.query.get($v{argName}) : null));
                return switch prim {
                    case "Int":
                        if (isOpt) {
                            // NOTE: Using 0 as default may mask invalid input; consider returning null or sending 400.
                            macro($base != null ? (function(__s:String) {
                                var __v = Std.parseInt(__s);
                                return (__v == null ? 0 : __v);
                            })($base) : 0);
                        } else {
                            macro(function(__s:String) {
                                var __v = Std.parseInt(__s);
                                return (__v == null ? 0 : __v);
                            })($base);
                        }
                    case "Float":
                        if (isOpt) {
                            macro($base != null ? Std.parseFloat($base) : 0.0);
                        } else {
                            macro Std.parseFloat($base);
                        }
                    case "Bool":
                        // NOTE: Treats missing bool as false; consider null instead.
                        if (isOpt) {
                            macro($base != null ? ($base == "true" || $base == "1") : false);
                        } else {
                            macro($base != null ? ($base == "true" || $base == "1") : false);
                        }
                    case _: base;
                };
            } else {
                // For complex types: try field inside JSON body else pass whole body (may be ambiguous if multiple).
                // Consider: if multiple complex args, this logic may not discriminate; enhance by requiring object root fields.
                var access:Expr = macro(req.jsonBody != null
                    && Reflect.hasField(req.jsonBody, $v{argName}) ? Reflect.field(req.jsonBody, $v{argName}) : req.jsonBody);
                return access;
            }
        }

        var type = Context.getType(ifaceExpr.toString());

        switch (type) {
            case TInst(t, _):
                var cl = t.get();
                if (!cl.isInterface) {
                    Context.error('${cl.name} is not an interface', ifaceExpr.pos);
                }

                for (field in cl.fields.get()) {
                    switch (field.kind) {
                        case FMethod(_):
                            var httpMethod = "";
                            var path = "";
                            var requiresAuth = false;
                            for (m in field.meta.get()) {
                                switch (m.name) {
                                    case "get", "post", "put", "delete":
                                        httpMethod = m.name;
                                        if (m.params.length > 0) {
                                            var p = m.params[0];
                                            switch (p.expr) {
                                                case EConst(CString(s)):
                                                    path = s;
                                                default:
                                                    Context.error('Expected string literal in meta', p.pos);
                                            }
                                        }
                                    case "requiresAuth":
                                        requiresAuth = true;
                                    default:
                                }
                            }

                            if (httpMethod == "" || path == "")
                                continue;

                            switch (field.type) {
                                case TFun(args, ret):
                                    var callArgs:Array<Expr> = [];
                                    var hasUserIdParam = false;
                                    var userIdParamIndex = -1;
                                    
                                    // Check if there's a userId parameter
                                    for (i in 0...args.length) {
                                        if (args[i].name == "userId" && TypeTools.toString(args[i].t) == "String") {
                                            hasUserIdParam = true;
                                            userIdParamIndex = i;
                                            break;
                                        }
                                    }
                                    
                                    for (i in 0...args.length) {
                                        var arg = args[i];
                                        // Skip userId parameter - we'll inject it later if requiresAuth
                                        if (arg.name == "userId" && hasUserIdParam) {
                                            callArgs.push(macro null); // placeholder
                                        } else {
                                            callArgs.push(buildArgAccess(arg.name, arg.t, arg.opt));
                                        }
                                    }

                                    var followedRet = Context.follow(ret);
                                    var retName = TypeTools.toString(followedRet);
                                    inline function isVoid():Bool
                                        return retName == "Void";
                                    inline function isPrimitive():Bool
                                        return (retName == "Int" || retName == "Float" || retName == "Bool" || retName == "String");

                                    var methodName = field.name;

                                    // Build auth check if requiresAuth is true (always check session)
                                    var authCheck:Expr = if (requiresAuth) {
                                        macro {
                                            var __userId:String = null;
                                            var __sessionToken:String = null;
                                            trace("[AutoRouter] Checking for session_token in cookies...");
                                            // Extract session_token from cookies
                                            if (req.cookies != null && req.cookies.exists("session_token")) {
                                                __sessionToken = req.cookies.get("session_token");
                                                trace('[AutoRouter] Found session_token: ' + __sessionToken);
                                            } else {
                                                trace('[AutoRouter] session_token not found in cookies.');
                                            }

                                            // Fallback: Check Authorization header
                                            if (__sessionToken == null) {
                                                var authHeader = req.headers.get("Authorization");
                                                if (authHeader != null && authHeader.indexOf("Bearer ") == 0) {
                                                    __sessionToken = authHeader.substring(7);
                                                    trace('[AutoRouter] Found session_token in Authorization header: ' + __sessionToken);
                                                }
                                            }


                                            trace('[AutoRouter] Checking for userId in cache using session_token...');
                                            if (__sessionToken != null && $cacheExpr != null) {
                                                // Look up user from cache
                                                var cachedData = ($cacheExpr).get("session:" + __sessionToken);
                                                
                                                // Parse JSON if it's a string (since cache stores stringified JSON)
                                                if (cachedData != null && Std.isOfType(cachedData, String)) {
                                                    try {
                                                        cachedData = haxe.Json.parse(cachedData);
                                                    } catch (e:Dynamic) {
                                                        trace("[AutoRouter] Failed to parse cached session JSON: " + e);
                                                        cachedData = null;
                                                    }
                                                }

                                                if (cachedData != null) {
                                                    if (Reflect.hasField(cachedData, "id")) {
                                                        __userId = Reflect.field(cachedData, "id");
                                                        trace('[AutoRouter] Found userId: ' + __userId);
                                                    } else {
                                                        trace('[AutoRouter] userId not found in cachedData.');
                                                    }
                                                } else {
                                                    trace('[AutoRouter] No cachedData found for session_token.');
                                                }
                                            } else {
                                                trace('[AutoRouter] session_token or cacheExpr is null, cannot check userId.');
                                            }
                                            if (__userId == null) {
                                                trace('[AutoRouter] session not found, sending UNAUTHORIZED response.');
                                                res.sendResponse(snake.http.HTTPStatus.UNAUTHORIZED);
                                                res.setHeader("Content-Type", "application/json");
                                                res.endHeaders();
                                                res.write(haxe.Json.stringify({error: "Unauthorized - Authentication required"}));
                                                res.end();
                                                return;
                                            }
                                        };
                                    } else {
                                        macro {};
                                    };

                                    // Replace userId placeholder with actual value if needed
                                    if (requiresAuth && hasUserIdParam && userIdParamIndex >= 0) {
                                        callArgs[userIdParamIndex] = macro __userId;
                                    }

                                    // Handler body; consider wrapping in try/catch for 500 responses.
                                    var handler:Expr = if (isVoid()) {
                                        macro function(req, res) {
                                            var __userId:String = null;
                                            $authCheck;
                                            var inst = ($implExpr)();
                                            // TODO: try/catch
                                            inst.$methodName($a{callArgs});
                                            res.sendResponse(snake.http.HTTPStatus.OK);
                                            // Consider adding CORS headers centrally before endHeaders.
                                            res.endHeaders();
                                            res.end();
                                        };
                                    } else if (isPrimitive()) {
                                        macro function(req, res) {
                                            var __userId:String = null;
                                            $authCheck;
                                            var inst = ($implExpr)();
                                            var result = inst.$methodName($a{callArgs});
                                            res.sendResponse(snake.http.HTTPStatus.OK);
                                            res.setHeader("Content-Type", "application/json"); // changed to application/json
                                            var json = haxe.Json.stringify(result);
                                            res.setHeader('Content-Length', Std.string(json.length));
                                            res.endHeaders();
                                            res.write(json);
                                            res.end();
                                        };
                                    } else {
                                        macro function(req, res) {
                                            var __userId:String = null;
                                            $authCheck;
                                            var inst = ($implExpr)();
                                            var result = inst.$methodName($a{callArgs});
                                            res.sendResponse(snake.http.HTTPStatus.OK);
                                            res.setHeader("Content-Type", "application/json"); // changed to application/json
                                            var json = "";
                                            if ((cast result : Dynamic) != null)
                                                json = haxe.Json.stringify(result);
                                            res.setHeader('Content-Length', Std.string(json.length));
                                            res.endHeaders();
                                            res.write(json);
                                            res.end();
                                        };
                                    };

                                    // Register route; assumes upper-case method matching router expectations.
                                    var addRoute:Expr = switch httpMethod {
                                        case "get": macro __autoRouter.add("GET", $v{path}, $handler);
                                        case "post": macro __autoRouter.add("POST", $v{path}, $handler);
                                        case "put": macro __autoRouter.add("PUT", $v{path}, $handler);
                                        case "delete": macro __autoRouter.add("DELETE", $v{path}, $handler);
                                        default: null;
                                    };

                                    if (addRoute != null) routeExprs.push(addRoute);

                                default:
                                    Context.error('Unexpected non-function type on method', field.pos);
                            }

                        default:
                    }
                }

            default:
                Context.error('Expected an interface type, got ' + TypeTools.toString(type), ifaceExpr.pos);
        }

        return macro {
            var __autoRouter = $routerExpr;
            $b{routeExprs};
        };
    }
}
