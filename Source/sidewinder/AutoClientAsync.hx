package sidewinder;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.io.BytesOutput; // for customRequest output capture (PUT/DELETE)
using haxe.macro.TypeTools;
using haxe.macro.ExprTools;

/**
 * Macro that generates an asynchronous client for a service interface annotated with @get/@post/@put/@delete.
 * Each interface method "foo" becomes "fooAsync" with signature:
 *   fooAsync(args..., onSuccess:RetType->Void, ?onError:Dynamic->Void):Void
 * Primitive return types are passed directly; JSON bodies are parsed for object/array types.
 */
class AutoClientAsync {
    public static macro function create(iface:Expr, baseUrl:Expr):Expr {
        var ifaceName = switch (iface.expr) {
            case EConst(CIdent(s)): s;
            default: Context.error("Expected interface identifier", iface.pos); "";
        };
        var t = Context.getType(ifaceName);
        switch (t) {
            case TInst(clRef, _):
                var cl = clRef.get();
                if (!cl.isInterface) Context.error(cl.name + " is not an interface", iface.pos);
                var uniqueName = cl.name + "_AutoClientAsync_" + Std.string(Std.random(999999));
                var fields:Array<Field> = [];
                // baseUrl field & ctor
                fields.push({
                    name: "baseUrl",
                    access: [APublic],
                    kind: FVar(macro:String, null),
                    pos: Context.currentPos()
                });
                fields.push({
                    name: "new",
                    access: [APublic],
                    kind: FFun({
                        args: [ { name: "baseUrl", type: macro:String } ],
                        expr: macro this.baseUrl = baseUrl,
                        params: [],
                        ret: null
                    }),
                    pos: Context.currentPos()
                });
                // helper doRequestAsync
                fields.push({
                    name: "doRequestAsync",
                    access: [APrivate],
                    kind: FFun({
                        args: [
                            { name: "method", type: macro:String },
                            { name: "path", type: macro:String },
                            { name: "body", type: macro:Dynamic },
                            { name: "onData", type: macro:String->Void },
                            { name: "onError", type: macro:Dynamic->Void }
                        ],
                        params: [],
                        ret: macro:Void,
                        expr: macro {
                            var full = baseUrl + path;
                            var jsonBody = (body != null) ? haxe.Json.stringify(body) : null;
                            var h = new haxe.Http(full);
                            h.setHeader("Accept", "application/json");
                            if (jsonBody != null) {
                                h.setHeader("Content-Type", "application/json");
                                h.setPostData(jsonBody);
                            }
                            h.onError = function(e:String) onError(e);
                            // Use customRequest for verbs beyond GET/POST (PUT/DELETE) as per gist reference.
                            if (method == "PUT" || method == "DELETE") {
                                var out:haxe.io.BytesOutput = new haxe.io.BytesOutput();
                                try {
                                    // post flag true if we have a body; method passed explicitly.
                                    h.customRequest(jsonBody != null, out, method);
                                    var respStr = out.getBytes().toString();
                                    onData(respStr);
                                } catch (e:Dynamic) {
                                    onError(e);
                                }
                            } else {
                                // GET/POST handled by request; POST when body or explicit method
                                h.onData = function(d:String) onData(d);
                                try h.request(method == "POST") catch (e:Dynamic) onError(e);
                            }
                        }
                    }),
                    pos: Context.currentPos()
                });

                for (field in cl.fields.get()) {
                    switch (field.kind) {
                        case FMethod(_):
                            var httpMethod = "";
                            var path = "";
                            for (m in field.meta.get()) {
                                switch (m.name) {
                                    case "get", "post", "put", "delete":
                                        httpMethod = m.name.toUpperCase();
                                        if (m.params.length > 0) {
                                            var p = m.params[0];
                                            switch (p.expr) {
                                                case EConst(CString(s)): path = s;
                                                default: Context.error("Expected string literal in meta", p.pos);
                                            }
                                        }
                                    default:
                                }
                            }
                            if (httpMethod == "" || path == "") continue; // skip unannotated
                            switch (field.type) {
                                case TFun(args, ret):
                                    var pathParamNames:Array<String> = [];
                                    for (segment in path.split("/")) if (StringTools.startsWith(segment, ":")) pathParamNames.push(segment.substr(1));
                                    var argDecls:Array<FunctionArg> = [];
                                    var renamed = new Map<String,String>();
                                    for (a in args) {
                                        var newName = pathParamNames.indexOf(a.name) != -1 ? '_' + a.name : a.name;
                                        renamed.set(a.name, newName);
                                        argDecls.push({ name: newName, type: Context.toComplexType(a.t) });
                                    }
                                    // Runtime URL building: start from literal path, replace :param tokens using renamed args
                                    var bodyExprs:Array<Expr> = [];
                                    bodyExprs.push(macro var _p = $v{path});
                                    for (pp in pathParamNames) {
                                        var renamedIdent = renamed.get(pp);
                                        var identExpr:Expr = { expr: EConst(CIdent(renamedIdent)), pos: Context.currentPos() };
                                        bodyExprs.push(macro _p = StringTools.replace(_p, ":" + $v{pp}, Std.string($identExpr)));
                                    }
                                    // Determine body arg (first non-path param for POST/PUT)
                                    var bodyArg:Null<String> = null;
                                    if (httpMethod == "POST" || httpMethod == "PUT") {
                                        for (a in args) if (pathParamNames.indexOf(a.name) == -1) { bodyArg = renamed.get(a.name); break; }
                                    }
                                    var bodyExpr:Expr = (bodyArg != null) ? macro $i{bodyArg} : macro null;
                                    var followedRet = Context.follow(ret);
                                    var retName = TypeTools.toString(followedRet);
                                    // Add async callback args
                                    // Special case void return: callback takes no parameters
                                    var voidType:ComplexType = TPath({ pack: [], name: "Void", params: [] });
                                    if (retName == "Void") {
                                        argDecls.push({ name: "onSuccess", type: TFunction([], voidType) });
                                    } else {
                                        argDecls.push({ name: "onSuccess", type: TFunction([Context.toComplexType(ret)], voidType) });
                                    }
                                    argDecls.push({ name: "onFailure", type: macro:Dynamic->Void });
                                    var parseExpr:Expr;
                                    if (retName == "Void") {
                                        parseExpr = macro onSuccess();
                                    } else if (retName == "Int") {
                                        parseExpr = macro {
                                            var parsed = Std.parseInt(d);
                                            onSuccess(parsed == null ? 0 : parsed);
                                        };
                                    } else if (retName == "Float") {
                                        parseExpr = macro onSuccess(Std.parseFloat(d));
                                    } else if (retName == "Bool") {
                                        parseExpr = macro {
                                            var s = d;
                                            onSuccess(s == "true" || s == "1");
                                        };
                                    } else if (retName == "String") {
                                        parseExpr = macro onSuccess(d);
                                    } else {
                                        parseExpr = macro {
                                            if (d == null || d == "") onSuccess(null) else {
                                                try onSuccess(haxe.Json.parse(d)) catch (e:Dynamic) onFailure(e);
                                            }
                                        };
                                    }
                                    bodyExprs.push(macro doRequestAsync($v{httpMethod}, _p, $bodyExpr, function(d:String) $parseExpr, function(e:Dynamic) onFailure(e)));
                                    var methodBody:Expr = { expr: EBlock(bodyExprs), pos: Context.currentPos() };
                                    fields.push({
                                        name: field.name + "Async",
                                        access: [APublic],
                                        kind: FFun({ args: argDecls, params: [], ret: macro:Void, expr: methodBody }),
                                        pos: field.pos
                                    });
                                default:
                            }
                        default:
                    }
                }
                var ifaceTypePath:TypePath = { pack: cl.pack, name: cl.name };
                var classDef:TypeDefinition = {
                    pack: ["sidewinder"],
                    name: uniqueName,
                    pos: Context.currentPos(),
                    meta: [],
                    params: [],
                    isExtern: false,
                    // Do NOT implement the interface to avoid needing sync method bodies
                    kind: TDClass(null, [], false),
                    fields: fields
                };
                Context.defineType(classDef);
                var typePath:TypePath = { pack: ["sidewinder"], name: uniqueName };
                return { expr: ENew(typePath, [baseUrl]), pos: Context.currentPos() };
            case _: Context.error("Expected interface type", iface.pos); return macro null;
        }
    }
}
