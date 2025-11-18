package sidewinder;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.TypeTools;
using haxe.macro.ExprTools;

class AutoClient {
    public static macro function create(iface:Expr, baseUrl:Expr):Expr {
        var ifaceName = switch (iface.expr) {
            case EConst(CIdent(s)): s;
            default: Context.error("Expected interface identifier", iface.pos); "";
        };
        var t = Context.getType(ifaceName);
        switch (t) {
            case TInst(clRef, _):
                var cl = clRef.get();
                if (!cl.isInterface)
                    Context.error(cl.name + " is not an interface", iface.pos);
                var uniqueName = cl.name + "_AutoClient_" + Std.string(Std.random(999999));
                var fields:Array<Field> = [];
                fields.push({
                    name: "baseUrl",
                    access: [APublic],
                    kind: FVar(macro:String, null),
                    pos: Context.currentPos()
                });
                fields.push({
                    name: "cookieJar",
                    access: [APublic, AStatic],
                    kind: FVar(macro:sidewinder.CookieJar, macro new sidewinder.CookieJar()),
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
                fields.push({
                    name: "doRequest",
                    access: [APrivate],
                    kind: FFun({
                        args: [
                            { name: "method", type: macro:String },
                            { name: "path", type: macro:String },
                            { name: "body", type: macro:Dynamic }
                        ],
                        ret: macro:Dynamic,
                        expr: macro {
                                var fullUrl = baseUrl + path;
                                var jsonBody = (body != null) ? haxe.Json.stringify(body) : null;
                                var result:Dynamic = null;
                                var error:Dynamic = null;
                                var done = false;
                                var h = new haxe.Http(fullUrl);
                                h.setHeader("Accept", "application/json");
                                if (jsonBody != null) {
                                    h.setHeader("Content-Type", "application/json");
                                    h.setPostData(jsonBody);
                                }
                                
                                // Add cookies for sys targets
                                #if sys
                                var cookieHeader = cookieJar.getCookieHeader(fullUrl);
                                if (cookieHeader != "") {
                                    h.setHeader("Cookie", cookieHeader);
                                }
                                #end
                                
                                h.onData = function(data:String) {
                                    result = data;
                                    done = true;
                                };
                                h.onError = function(msg:String) {
                                    error = msg;
                                    done = true;
                                };
                                
                                // Store response headers callback for sys targets
                                #if sys
                                h.onStatus = function(status:Int) {
                                    // Access response headers via cnxInfos
                                    try {
                                        var headers = h.responseHeaders;
                                        if (headers != null) {
                                            for (key in headers.keys()) {
                                                if (key.toLowerCase() == "set-cookie") {
                                                    var setCookieValue = headers.get(key);
                                                    if (setCookieValue != null) {
                                                        cookieJar.setCookie(setCookieValue, fullUrl);
                                                    }
                                                }
                                            }
                                        }
                                    } catch (e:Dynamic) {
                                        // Silently ignore header parsing errors
                                    }
                                };
                                #end
                                
                                // request(true) performs POST/PUT if postData set, GET otherwise; override via method if needed
                                try h.request(method != "GET") catch (e:Dynamic) { error = e; done = true; }
                                // Busy spin (cross-target) to emulate sync; remove Sys.sleep to allow html5 build.
                                var start = haxe.Timer.stamp();
                                while (!done && (haxe.Timer.stamp() - start) < 5) {
                                    // spin; consider refactoring to async API returning Future
                                }
                                if (error != null) return null;
                                return result;
                        }
                    }),
                    pos: Context.currentPos()
                });
                for (field in cl.fields.get()) {
                    switch (field.kind) {
                        case FMethod(_):
                            var httpMethod = "";
                            var path = "";
                            var requiresAuth = false;
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
                                    case "requiresAuth":
                                        requiresAuth = true;
                                    default:
                                }
                            }
                            if (httpMethod == "" || path == "") continue;
                            switch (field.type) {
                                case TFun(args, ret):
                                    var pathParamNames = [];
                                    for (segment in path.split("/")) {
                                        if (StringTools.startsWith(segment, ":")) pathParamNames.push(segment.substr(1));
                                    }
                                    var argDecls = [];
                                    for (a in args) {
                                        // Skip userId parameter if @requiresAuth is set
                                        if (requiresAuth && a.name == "userId") {
                                            continue;
                                        }
                                        argDecls.push({ name: a.name, type: Context.toComplexType(a.t) });
                                    }
                                    var urlBuilderParts:Array<Expr> = [];
                                    var segments = path.split("/");
                                    for (seg in segments) {
                                        if (seg == "") continue;
                                        if (StringTools.startsWith(seg, ":")) {
                                            var pname = seg.substr(1);
                                            urlBuilderParts.push(macro Std.string($i{pname}));
                                        } else {
                                            urlBuilderParts.push(macro $v{seg});
                                        }
                                    }
                                    var joinExpr:Expr = if (urlBuilderParts.length == 0) {
                                        macro "";
                                    } else {
                                        var e = urlBuilderParts[0];
                                        for (i in 1...urlBuilderParts.length) {
                                            e = macro $e + "/" + ${urlBuilderParts[i]};
                                        }
                                        e;
                                    };
                                    var fullPathExpr = macro "/" + $joinExpr;
                                    var bodyArg:Null<String> = null;
                                    if (httpMethod == "POST" || httpMethod == "PUT") {
                                        for (a in args) if (pathParamNames.indexOf(a.name) == -1) bodyArg = a.name;
                                    }
                                    var bodyExpr:Expr = (bodyArg != null) ? macro $i{bodyArg} : macro null;
                                    var followedRet = Context.follow(ret);
                                    var retName = TypeTools.toString(followedRet);
                                    var methodBody:Expr;
                                    if (retName == "Void") {
                                        methodBody = macro {
                                            doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                        };
                                    } else if (retName == "Int") {
                                        methodBody = macro {
                                            var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                            if (resp == null) return 0;
                                            var parsed = Std.parseInt(Std.string(resp));
                                            return parsed == null ? 0 : parsed;
                                        };
                                    } else if (retName == "Float") {
                                        methodBody = macro {
                                            var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                            return resp == null ? 0.0 : Std.parseFloat(Std.string(resp));
                                        };
                                    } else if (retName == "Bool") {
                                        methodBody = macro {
                                            var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                            var s = Std.string(resp);
                                            return (s == "true" || s == "1");
                                        };
                                    } else if (retName == "String") {
                                        methodBody = macro {
                                            var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                            return resp == null ? null : Std.string(resp);
                                        };
                                    } else {
                                        methodBody = macro {
                                            var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                            if (resp == null || Std.string(resp) == "") return null;
                                            try {
                                                return haxe.Json.parse(Std.string(resp));
                                            } catch (e:Dynamic) {
                                                return null;
                                            }
                                        };
                                    }
                                    fields.push({
                                        name: field.name,
                                        access: [APublic],
                                        kind: FFun({
                                            args: argDecls,
                                            params: [],
                                            ret: Context.toComplexType(ret),
                                            expr: methodBody
                                        }),
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
                    kind: TDClass(null, [ifaceTypePath], false),
                    fields: fields
                };
                Context.defineType(classDef);
                var typePath:TypePath = { pack: ["sidewinder"], name: uniqueName };
                return { expr: ENew(typePath, [baseUrl]), pos: Context.currentPos() };
            case _: Context.error("Expected interface type", iface.pos); return macro null;
        }
    }
}
