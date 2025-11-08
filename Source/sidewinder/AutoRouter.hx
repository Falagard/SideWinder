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
 * Notes:
 *   - No try/catch or error normalization is currently added.
 *   - Complex arg resolution is simplistic (falls back to entire req.jsonBody).
 *   - All handlers are synchronous; async/promise return types are not handled.
 */
class AutoRouter {
    public static macro function build(routerExpr:Expr, ifaceExpr:Expr, implExpr:Expr):Expr {
        var router = routerExpr;
        var routeExprs:Array<Expr> = [];

        // Build expression that extracts an argument value from request (path params or JSON body).
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
                // Path/query parameters assumed to be already populated in req.params.
                var base:Expr = macro req.params.get($v{argName});
                if (isOpt)
                    base = macro(req.params.exists($v{argName}) ? req.params.get($v{argName}) : null);
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
                                    default:
                                }
                            }

                            if (httpMethod == "" || path == "")
                                continue;

                            switch (field.type) {
                                case TFun(args, ret):
                                    var callArgs:Array<Expr> = [];
                                    for (arg in args) {
                                        callArgs.push(buildArgAccess(arg.name, arg.t, arg.opt));
                                    }

                                    var followedRet = Context.follow(ret);
                                    var retName = TypeTools.toString(followedRet);
                                    inline function isVoid():Bool
                                        return retName == "Void";
                                    inline function isPrimitive():Bool
                                        return (retName == "Int" || retName == "Float" || retName == "Bool" || retName == "String");

                                    var methodName = field.name;

                                    // Handler body; consider wrapping in try/catch for 500 responses.
                                    var handler:Expr = if (isVoid()) {
                                        macro function(req, res) {
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
