package sidewinder;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

class AutoRouter {
	public static macro function build(routerExpr:Expr, ifaceExpr:Expr, implExpr:Expr):Expr {
		var router = routerExpr;
		var routeExprs:Array<Expr> = [];

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
				var base:Expr = macro req.params.get($v{argName});
				if (isOpt)
					base = macro(req.params.exists($v{argName}) ? req.params.get($v{argName}) : null);
				return switch prim {
					case "Int":
						if (isOpt) {
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
						if (isOpt) {
							macro($base != null ? ($base == "true" || $base == "1") : false);
						} else {
							macro($base != null ? ($base == "true" || $base == "1") : false);
						}
					case _: base;
				};
			} else {
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

									var handler:Expr = if (isVoid()) {
										macro function(req, res) {
											var inst = ($implExpr)();
											inst.$methodName($a{callArgs});
                                            res.sendResponse(snake.http.HTTPStatus.OK);
                                            res.endHeaders();
											res.end();
										};
									} else if (isPrimitive()) {
										macro function(req, res) {
											var inst = ($implExpr)();
											var result = inst.$methodName($a{callArgs});
                                            res.sendResponse(snake.http.HTTPStatus.OK);
                                            res.setHeader("Content-Type", "text/json");
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
                                            res.setHeader("Content-Type", "text/json");
                                            var json = "";
											if ((cast result : Dynamic) != null)
												json = haxe.Json.stringify(result);
                                            res.setHeader('Content-Length', Std.string(json.length));
                                            res.endHeaders();
                                            res.write(json);
											res.end();
										};
									};

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
