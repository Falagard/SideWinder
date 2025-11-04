package sidewinder;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.TypeTools;

/**
 * AutoClient builds a client-side proxy implementation of a SideWinder service interface.
 *
 * It inspects an interface for methods annotated with @get, @post, @put, @delete metadata (same as AutoRouter)
 * and generates an implementation that performs blocking HTTP calls to a remote server whose baseUrl you provide.
 *
 * Usage:
 *   var userClient:IUserService = AutoClient.create(IUserService, "http://localhost:8080");
 *
 * Limitations / Assumptions:
 * - Only supports http (not https).
 * - Primitive and object JSON responses are supported (object responses use haxe.Json.parse).
 * - For POST/PUT the request body is taken from the last argument that is NOT a path parameter.
 * - Path parameters use the ":param" syntax as in the server router and are substituted from method arguments.
 * - Synchronous (blocking) calls implemented via sys.net.Socket; suitable for sys targets.
 */
class AutoClient {
    /** Macro that returns an instance implementing the given interface */
    public static macro function create(iface:Expr, baseUrl:Expr):Expr {
        var t = Context.getType(iface.toString());
        switch (t) {
            case TInst(clRef, _):
                var cl = clRef.get();
                if (!cl.isInterface)
                    Context.error(cl.name + " is not an interface", iface.pos);

                // Build a new class definition implementing this interface
                var uniqueName = Context.generateUniqueName(cl.name + "_AutoClient");

                var fields:Array<Field> = [];

                // Store baseUrl
                fields.push({
                    name: "baseUrl",
                    access: [APublic],
                    kind: FVar(macro:String, null),
                    pos: Context.currentPos()
                });

                // Constructor
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

                // Helper: perform blocking request
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
                            var url = baseUrl;
                            if (StringTools.startsWith(url, "http://")) url = url.substr(7); // strip scheme
                            var prefix = "";
                            var slashIdx = url.indexOf("/");
                            var hostPort = if (slashIdx == -1) url else url.substr(0, slashIdx);
                            prefix = if (slashIdx == -1) "" else url.substr(slashIdx); // includes leading slash
                            var hp = hostPort.split(":");
                            var host = hp[0];
                            var port = (hp.length > 1) ? Std.parseInt(hp[1]) : 80;
                            if (port == null) port = 80;

                            var requestPath = prefix + path; // path already begins with '/'
                            var jsonBody = (body != null) ? haxe.Json.stringify(body) : null;
                            var contentLength = (jsonBody != null) ? jsonBody.length : 0;
                            var sb = new StringBuf();
                            sb.add(method + " " + requestPath + " HTTP/1.1\r\n");
                            sb.add("Host: " + host + "\r\n");
                            sb.add("Accept: application/json\r\n");
                            if (jsonBody != null) sb.add("Content-Type: application/json\r\n");
                            if (jsonBody != null) sb.add("Content-Length: " + contentLength + "\r\n");
                            sb.add("Connection: close\r\n\r\n");
                            if (jsonBody != null) sb.add(jsonBody);

                            var sock = new sys.net.Socket();
                            try {
                                sock.connect(new sys.net.Host(host), port);
                                sock.output.writeString(sb.toString());
                                sock.output.flush();
                            } catch (e:Dynamic) {
                                try sock.close() catch (_:Dynamic) {}
                                return null;
                            }

                            var input = sock.input;
                            var statusLine = "";
                            try statusLine = input.readLine() catch (e:Dynamic) statusLine = "";
                            var status = 0;
                            if (statusLine != null && statusLine.indexOf(" ") != -1) {
                                var parts = statusLine.split(" ");
                                if (parts.length >= 2) status = Std.parseInt(parts[1]);
                            }
                            var headers = new Map<String,String>();
                            while (true) {
                                var line = "";
                                try line = input.readLine() catch (e:Dynamic) line = null;
                                if (line == null || line == "") break;
                                var idx = line.indexOf(":");
                                if (idx != -1) {
                                    var hk = StringTools.trim(line.substr(0, idx));
                                    var hv = StringTools.trim(line.substr(idx + 1));
                                    headers.set(hk, hv);
                                }
                            }
                            var bodyStr = "";
                            var contentLenHeader = headers.get("Content-Length");
                            if (contentLenHeader != null) {
                                var len = Std.parseInt(contentLenHeader);
                                if (len != null && len > 0) {
                                    var bytes = haxe.io.Bytes.alloc(len);
                                    input.readFullBytes(bytes, 0, len);
                                    bodyStr = bytes.toString();
                                }
                            } else {
                                // Fallback: read remainder until close
                                try {
                                    while (true) {
                                        var b = input.readByte();
                                        bodyStr += String.fromCharCode(b);
                                    }
                                } catch (_:Dynamic) {}
                            }
                            try sock.close() catch (_:Dynamic) {}

                            if (status >= 400) return null; // treat errors as null
                            return bodyStr;
                        }
                    }),
                    pos: Context.currentPos()
                });

                // Process interface methods
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
                                                case EConst(CString(s)):
                                                    path = s;
                                                default:
                                                    Context.error('Expected string literal in meta', p.pos);
                                            }
                                        }
                                    default:
                                }
                            }
                            if (httpMethod == "" || path == "") continue;

                            switch (field.type) {
                                case TFun(args, ret):
                                    // Collect path params
                                    var pathParamNames = [];
                                    for (segment in path.split('/')) {
                                        if (StringTools.startsWith(segment, ':')) pathParamNames.push(segment.substr(1));
                                    }
                                    var argDecls = [];
                                    for (a in args) {
                                        argDecls.push({ name: a.name, type: Context.toComplexType(a.t) });
                                    }

                                    // Build URL construction expression
                                    var urlBuilderParts:Array<Expr> = [];
                                    var segments = path.split('/');
                                    for (seg in segments) {
                                        if (seg == "") continue;
                                        if (StringTools.startsWith(seg, ':')) {
                                            var pname = seg.substr(1);
                                            urlBuilderParts.push(macro Std.string($i{pname}));
                                        } else {
                                            urlBuilderParts.push(macro $v{seg});
                                        }
                                    }
                                    var joinExpr:Expr = if (urlBuilderParts.length == 0) macro "" else {
                                        // Concatenate with '/'
                                        var e = urlBuilderParts[0];
                                        for (i in 1...urlBuilderParts.length) {
                                            e = macro $e + "/" + ${urlBuilderParts[i]};
                                        }
                                        e;
                                    };
                                    var fullPathExpr = macro "/" + $joinExpr; // ensure leading slash

                                    // Determine body argument (last non-path arg for POST/PUT)
                                    var bodyArg:Null<String> = null;
                                    if (httpMethod == "POST" || httpMethod == "PUT") {
                                        for (a in args) if (pathParamNames.indexOf(a.name) == -1) bodyArg = a.name;
                                    }
                                    var bodyExpr:Expr = (bodyArg != null) ? macro $i{bodyArg} : macro null;

                                    var followedRet = Context.follow(ret);
                                    var retName = TypeTools.toString(followedRet);
                                    inline function isVoid() return retName == "Void";
                                    inline function isPrimitive() return retName == "Int" || retName == "Float" || retName == "Bool" || retName == "String";

                                    var methodBody:Expr = if (isVoid()) {
                                        macro {
                                            doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                        };
                                    } else if (isPrimitive()) {
                                        switch (retName) {
                                            case "Int": methodBody = macro {
                                                var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                                return resp == null ? 0 : Std.parseInt(Std.string(resp));
                                            };
                                            case "Float": methodBody = macro {
                                                var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                                return resp == null ? 0.0 : Std.parseFloat(Std.string(resp));
                                            };
                                            case "Bool": methodBody = macro {
                                                var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                                var s = Std.string(resp);
                                                return (s == "true" || s == "1");
                                            };
                                            case "String": methodBody = macro {
                                                var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                                return resp == null ? null : Std.string(resp);
                                            };
                                            default: methodBody = macro null; // unreachable
                                        }
                                        methodBody;
                                    } else {
                                        // Object / Array etc.
                                        methodBody = macro {
                                            var resp:Dynamic = doRequest($v{httpMethod}, $fullPathExpr, $bodyExpr);
                                            if (resp == null || Std.string(resp) == "") return null;
                                            try {
                                                return haxe.Json.parse(Std.string(resp));
                                            } catch (e:Dynamic) {
                                                return null;
                                            }
                                        };
                                        methodBody;
                                    };

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

                // Define the class type
                var classDef:TypeDefinition = {
                    pack: ["sidewinder"],
                    name: uniqueName,
                    pos: Context.currentPos(),
                    meta: [],
                    params: [],
                    isExtern: false,
                    kind: TDClass(null, [t], false), // implements interface
                    fields: fields
                };
                Context.defineType(classDef);
                // Return instantiation expression using dynamic type path
                var typePath:TypePath = { pack: ["sidewinder"], name: uniqueName };
                return { expr: ENew(typePath, [baseUrl]), pos: Context.currentPos() };
            case _: Context.error('Expected interface type', iface.pos); return macro null;
        }
    }
}
