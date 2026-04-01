package sidewinder.routing;

import sidewinder.interfaces.User;
import sidewinder.logging.HybridLogger;
import sidewinder.routing.Router;
import snake.http.HTTPStatus;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

/**
 * Macro that inspects an interface annotated with @get/@post/@put/@delete and
 * auto-registers concrete route handlers on a supplied router.
 */
class AutoRouter {

	public static macro function build(routerExpr:Expr, ifaceExpr:Expr, implExpr:Expr, ?cacheExpr:Expr):Expr {
		trace('--- MACRO RUNNING FOR: ' + ifaceExpr.toString());
		var router = routerExpr;
		var routeExprs:Array<Expr> = [];

		// Build expression that extracts an argument value from request (path params, query params, or JSON body).
		function buildArgAccess(lookupName:String, t:Type, isOpt:Bool):Expr {
			var typeStr = TypeTools.toString(t);
			var isOptional = isOpt || typeStr.indexOf("Null<") != -1;
			
			var conversion:Expr = macro __val;
			if (typeStr.indexOf("Int") != -1) {
				conversion = macro (__val != null ? Std.parseInt(Std.string(__val)) : ($v{isOptional} ? null : (cast 0 : Int)));
			} else if (typeStr.indexOf("Float") != -1) {
				conversion = macro (__val != null ? Std.parseFloat(Std.string(__val)) : ($v{isOptional} ? null : 0.0));
			} else if (typeStr.indexOf("Bool") != -1) {
				conversion = macro (__val != null ? (Std.string(__val).toLowerCase() == "true") : ($v{isOptional} ? null : false));
			} else if (typeStr.indexOf("String") != -1) {
				conversion = macro (__val != null ? Std.string(__val) : null);
			} else {
				// Complex type: parsing from body or JSON string
				conversion = macro {
					var __json:Dynamic = null;
					var __v:Dynamic = __val;
					if (__v != null) {
						if (Std.isOfType(__v, String)) {
							try { __json = haxe.Json.parse(__v); } catch(e:Dynamic) {}
						} else {
							__json = __v;
						}
					}
					if (__json == null && __rtReq.jsonBody != null) {
						if (Reflect.hasField(__rtReq.jsonBody, $v{lookupName})) __json = Reflect.field(__rtReq.jsonBody, $v{lookupName});
						else __json = __rtReq.jsonBody;
					}
					__json;
				};
			}

			// Use a totally unique name for __val to avoid any collision
			var uniqueValName = "__val_" + lookupName.split("-").join("_").split(".").join("_");

			return macro {
				var $uniqueValName:Dynamic = null;
				var __name = $v{lookupName};
				var __nameLower = __name.toLowerCase();
				
				if (__rtReq.params != null && __rtReq.params.exists(__name)) {
					$i{uniqueValName} = __rtReq.params.get(__name);
				} else if (__rtReq.params != null && __rtReq.params.exists(__nameLower)) {
					$i{uniqueValName} = __rtReq.params.get(__nameLower);
				} else if (__rtReq.query != null && __rtReq.query.exists(__name)) {
					$i{uniqueValName} = __rtReq.query.get(__name);
				} else if (__rtReq.query != null && __rtReq.query.exists(__nameLower)) {
					$i{uniqueValName} = __rtReq.query.get(__nameLower);
				} else if (__rtReq.jsonBody != null) {
					if (Reflect.hasField(__rtReq.jsonBody, __name)) {
						$i{uniqueValName} = Reflect.field(__rtReq.jsonBody, __name);
					} else {
						// For complex types, if the name isn't found, try the root body
						var typeStr = $v{typeStr};
						if (typeStr != "String" && typeStr != "Int" && typeStr != "Float" && typeStr != "Bool") {
							$i{uniqueValName} = __rtReq.jsonBody;
						}
					}
				}
				
				var __val = $i{uniqueValName};
				$conversion;
			};
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
							var routesToRegister = [];
							var requiresAuth = false;
							var requiredPermission:String = null;
							for (m in field.meta.get()) {
								switch (m.name) {
									case "get", "post", "put", "delete", "patch":
										var method = m.name;
										var routePath = "";
										if (m.params.length > 0) {
											var p = m.params[0];
											switch (p.expr) {
												case EConst(CString(s)):
													routePath = s;
												default:
													Context.error('Expected string literal in meta', p.pos);
											}
										}
										if (routePath != "") {
											routesToRegister.push({method: method, path: routePath});
										}
									case "requiresAuth":
										requiresAuth = true;
									case "requiresPermission":
										requiresAuth = true; // Implies auth
										if (m.params.length > 0) {
											var p = m.params[0];
											switch (p.expr) {
												case EConst(CString(s)):
													requiredPermission = s;
												default:
													Context.error('Expected string literal in @requiresPermission', p.pos);
											}
										}
									default:
								}
							}

							if (routesToRegister.length == 0)
								continue;

							switch (field.type) {
								case TFun(args, ret):
									var hasUserIdParam = false;
									var userIdParamIndex = -1;

									var headerInjections = new Map<String, String>();
									var queryInjections = new Map<String, String>();
									var pathInjections = new Map<String, String>();
									var bodyParam:String = null;
									
									for (m in field.meta.get()) {
										if (m.name == "headerParam" && m.params.length == 2) {
											var argName = switch (m.params[0].expr) { case EConst(CString(s)): s; default: null; };
											var headerName = switch (m.params[1].expr) { case EConst(CString(s)): s; default: null; };
											if (argName != null && headerName != null) headerInjections.set(argName, headerName);
										}
										if (m.name == "queryParam" && m.params.length == 2) {
											var argName = switch (m.params[0].expr) { case EConst(CString(s)): s; default: null; };
											var targetName = switch (m.params[1].expr) { case EConst(CString(s)): s; default: null; };
											if (argName != null && targetName != null) queryInjections.set(argName, targetName);
										}
										if (m.name == "pathParam" && m.params.length == 2) {
											var argName = switch (m.params[0].expr) { case EConst(CString(s)): s; default: null; };
											var targetName = switch (m.params[1].expr) { case EConst(CString(s)): s; default: null; };
											if (argName != null && targetName != null) pathInjections.set(argName, targetName);
										}
										if (m.name == "bodyParam" && m.params.length == 1) {
											bodyParam = switch (m.params[0].expr) { case EConst(CString(s)): s; default: null; };
										}
									}

									// Check if there's a userId parameter
									for (i in 0...args.length) {
										if (args[i].name == "userId" && TypeTools.toString(args[i].t) == "String") {
											hasUserIdParam = true;
											userIdParamIndex = i;
											break;
										}
									}

									var argVars:Array<Expr> = [];
									var callArgNames:Array<Expr> = [];

									var argNames = [for (a in args) a.name];
									trace('[AutoRouter] Processing ' + field.name + ' with args: ' + argNames.join(", "));
									for (i in 0...args.length) {
										var arg = args[i];
										var argName = arg.name;
										var varName = "__arg_" + i;
										callArgNames.push({ expr: EConst(CIdent(varName)), pos: Context.currentPos() });
										
										if (headerInjections.exists(argName)) {
											var hName = headerInjections.get(argName);
											argVars.push(macro var $varName = (function(headers:Map<String, String>) {
												if (headers == null) return null;
												if (headers.exists($v{hName})) return headers.get($v{hName});
												var lower = $v{hName.toLowerCase()};
												for (k in headers.keys()) {
													if (k.toLowerCase() == lower) return headers.get(k);
												}
												return null;
											})(__rtReq.headers));
										} else if (argName == bodyParam) {
											var argType = TypeTools.toString(arg.t);
											if (argType == "String" || argType == "Null<String>") {
												argVars.push(macro var $varName = __rtReq.body);
											} else {
												argVars.push(macro var $varName = __rtReq.jsonBody);
											}
										} else {
											var lookupName = argName;
											if (queryInjections.exists(argName)) lookupName = queryInjections.get(argName);
											if (pathInjections.exists(argName)) lookupName = pathInjections.get(argName);
											
											// Special handling for userId - only inject from session if NOT in path/query
											if (argName == "userId" && hasUserIdParam) {
												var isBoundToPath = false;
												for (r in routesToRegister) {
													if (r.path.indexOf(":" + lookupName) != -1 || r.path.indexOf(":*" + lookupName) != -1) {
														isBoundToPath = true;
														break;
													}
												}
												if (!isBoundToPath && !queryInjections.exists(argName)) {
													argVars.push(macro var $varName = __userId);
													continue;
												}
											}

											argVars.push(macro var $varName = ${buildArgAccess(lookupName, arg.t, arg.opt)});
										}
									}

									var followedRet = Context.follow(ret);
									var retName = TypeTools.toString(followedRet);
									inline function isVoid():Bool return retName == "Void";
									inline function isPrimitive():Bool return (retName == "Int" || retName == "Float" || retName == "Bool" || retName == "String");

									var methodName = field.name;

									// Trace request metadata for debugging
									var traceReq = macro {
										var paramsStr = "";
										if (__rtReq.params != null) {
											var pKeys = [];
											for (k in __rtReq.params.keys()) pKeys.push(k + " => " + __rtReq.params.get(k));
											paramsStr = "[" + pKeys.join(", ") + "]";
										}
										var queryStr = "";
										if (__rtReq.query != null) {
											var qKeys = [];
											for (k in __rtReq.query.keys()) qKeys.push(k + " => " + __rtReq.query.get(k));
											queryStr = "[" + qKeys.join(", ") + "]";
										}
										var bodyStr = (__rtReq.jsonBody != null ? haxe.Json.stringify(__rtReq.jsonBody) : "null");
										trace('[AutoRouter] ' + $v{methodName} + ' - Params: ' + paramsStr + ', Query: ' + queryStr + ', Body: ' + bodyStr);
									};

									// Build session extraction and auth check
									var authRun:Expr = macro {
										$traceReq;
										// 1. Try to get from AuthenticationMiddleware (__rtReq.params)
										if (__rtReq.params != null) {
											if (__rtReq.params.exists("auth_user_json")) {
												var __uJson = __rtReq.params.get("auth_user_json");
												try { __sessionData = haxe.Json.parse(__uJson); } catch (e:Dynamic) {}
											}
											if (__rtReq.params.exists("auth_user_id")) { __userId = __rtReq.params.get("auth_user_id"); }
											if (__rtReq.params.exists("auth_token")) { __sessionToken = __rtReq.params.get("auth_token"); }
										}

										// 2. Fallback extraction
										if (__sessionToken == null) {
											if (__rtReq.cookies != null && __rtReq.cookies.exists("session_token")) { __sessionToken = __rtReq.cookies.get("session_token"); }
											if (__sessionToken == null) {
												var authHeader = __rtReq.headers.get("Authorization");
												if (authHeader == null) authHeader = __rtReq.headers.get("authorization");
												if (authHeader != null && authHeader.indexOf("Bearer ") == 0) { __sessionToken = authHeader.substring(7); }
											}
										}
										if (__sessionToken != null && __sessionData == null && $cacheExpr != null) {
											var cached = ($cacheExpr).get("auth:session_by_token:" + __sessionToken);
											if (cached != null) {
												if (Std.isOfType(cached, String)) { try { __sessionData = haxe.Json.parse(cached); } catch (e:Dynamic) {} }
												else { __sessionData = cached; }
											}
										}
										if (__userId == null && __sessionData != null) {
											if (Reflect.hasField(__sessionData, "id")) __userId = Std.string(Reflect.field(__sessionData, "id"));
											else if (Reflect.hasField(__sessionData, "userId")) __userId = Std.string(Reflect.field(__sessionData, "userId"));
										}

										if ($v{requiresAuth} && __userId == null) {
											__rtRes.sendResponse(snake.http.HTTPStatus.UNAUTHORIZED);
											__rtRes.setHeader("Content-Type", "application/json");
											__rtRes.endHeaders();
											__rtRes.write(haxe.Json.stringify({error: "Unauthorized - Authentication required"}));
											__rtRes.end();
											return;
										}

										if ($v{requiresAuth} && $v{requiredPermission} != null) {
											var __hasPerm = false;
											if (__sessionData != null && Reflect.hasField(__sessionData, "permissions")) {
												var __perms:Array<Dynamic> = Reflect.field(__sessionData, "permissions");
												if (__perms != null) {
													for (__p in __perms) {
														var __ps = Std.string(__p);
														if (__ps == $v{requiredPermission} || __ps == "admin" || __ps == "*") { __hasPerm = true; break; }
													}
												}
											}
											if (!__hasPerm) {
												__rtRes.sendResponse(snake.http.HTTPStatus.FORBIDDEN);
												__rtRes.setHeader("Content-Type", "application/json");
												__rtRes.endHeaders();
												__rtRes.write(haxe.Json.stringify({error: "Forbidden - Missing permission: " + $v{requiredPermission}}));
												__rtRes.end();
												return;
											}
										}
									};

									var injectFields = macro {
										if (inst != null) {
											try { (cast inst).session = __sessionData; } catch(e:Dynamic) {}
											try { (cast inst).currentUser = __sessionData; } catch(e:Dynamic) {}
											try { (cast inst).currentToken = __sessionToken; } catch(e:Dynamic) {}
											try { (cast inst).userId = __userId; } catch(e:Dynamic) {}
										}
									};

									// Build the handler body as a flat list of expressions to avoid scope issues
									var handlerBody:Array<Expr> = [];
									handlerBody.push(macro var __userId:String = null);
									handlerBody.push(macro var __sessionToken:String = null);
									handlerBody.push(macro var __sessionData:Dynamic = null);
									handlerBody.push(authRun);
									handlerBody.push(macro var inst:Dynamic = ($implExpr)());
									handlerBody.push(injectFields);

									// Flat injection of argument variables
									for (v in argVars) handlerBody.push(v);

									handlerBody.push(macro trace('[AutoRouter] Calling ' + $v{methodName} + ' with args: ' + Std.string([ $a{callArgNames} ])));

									if (isVoid()) {
										handlerBody.push(macro inst.$methodName($a{callArgNames}));
										handlerBody.push(macro __rtRes.sendResponse(sidewinder.routing.StatusHelper.getStatus(200)));
										handlerBody.push(macro __rtRes.endHeaders());
										handlerBody.push(macro __rtRes.end());
									} else if (isPrimitive()) {
										handlerBody.push(macro var result = inst.$methodName($a{callArgNames}));
										handlerBody.push(macro __rtRes.sendResponse(sidewinder.routing.StatusHelper.getStatus(200)));
										handlerBody.push(macro __rtRes.setHeader("Content-Type", "application/json"));
										handlerBody.push(macro var json = haxe.Json.stringify(result));
										handlerBody.push(macro __rtRes.setHeader('Content-Length', Std.string(haxe.io.Bytes.ofString(json).length)));
										handlerBody.push(macro __rtRes.endHeaders());
										handlerBody.push(macro __rtRes.write(json));
										handlerBody.push(macro __rtRes.end());
									} else {
										handlerBody.push(macro var result = inst.$methodName($a{callArgNames}));
										handlerBody.push(macro trace('[AutoRouter] ' + $v{methodName} + ' returned: ' + Std.string(result)));
										handlerBody.push(macro {
											var __statusInt:Int = 200;
											var __cookies:Array<Dynamic> = null;

											if (result != null) {
												try {
													if (Reflect.hasField(result, "statusCode")) {
														var __v = Reflect.field(result, "statusCode");
														if (Std.isOfType(__v, Int)) __statusInt = (cast __v : Int);
													} else if (Reflect.hasField(result, "status")) {
														var __v = Reflect.field(result, "status");
														if (Std.isOfType(__v, Int)) __statusInt = (cast __v : Int);
													} else if (Reflect.hasField(result, "success")) {
														var __v = Reflect.field(result, "success");
														if (__v == false) __statusInt = 400;
													}
													if (Reflect.hasField(result, "cookies")) {
														__cookies = Reflect.field(result, "cookies");
													}
												} catch (e:Dynamic) {}
											}

											var json = "";
											try {
												json = (result != null ? haxe.Json.stringify(result) : "");
											} catch (e:Dynamic) {
												json = haxe.Json.stringify({error: "Serialization Error", message: Std.string(e)});
												__statusInt = 500;
											}

											__rtRes.sendResponse(sidewinder.routing.StatusHelper.getStatus(__statusInt));
											__rtRes.setHeader("Content-Type", "application/json");

											if (__cookies != null) {
												for (__c in __cookies) { __rtRes.setCookie(__c.name, __c.value, __c.options); }
											}

											__rtRes.endHeaders();
											__rtRes.write(json);
											__rtRes.end();
										});
									}

									// Final handler wrapping everything in a try-catch
									var handler = macro function(__rtReq, __rtRes) {
										try {
											$b{handlerBody}
										} catch (e:Dynamic) {
											var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
											trace('[AutoRouter] Error in ' + $v{methodName} + ': ' + Std.string(e) + '\nStack: ' + stack);
											sidewinder.logging.HybridLogger.error('[AutoRouter] Error in ' + $v{methodName} + ': ' + Std.string(e) + '\nStack: ' + stack);
											var errStr = Std.string(e);
											var __errStatusInt:Int = 500;
											if (errStr == "404") __errStatusInt = 404;
											else if (errStr == "403") __errStatusInt = 403;
											else if (errStr == "401") __errStatusInt = 401;
											else if (errStr.indexOf("UNIQUE constraint") != -1) __errStatusInt = 409;
											else if (errStr.indexOf("signature") != -1 || errStr.indexOf("Signature") != -1) __errStatusInt = 400;
											
											__rtRes.sendError(sidewinder.routing.StatusHelper.getStatus(__errStatusInt));
											__rtRes.endHeaders();
											if (__errStatusInt == 500) { __rtRes.write(haxe.Json.stringify({error: "Internal Server Error", message: errStr})); }
											else { __rtRes.write(haxe.Json.stringify({error: errStr})); }
											__rtRes.end();
										}
									};

									for (r in routesToRegister) {
										var addRoute:Expr = switch r.method {
											case "get": macro __autoRouter.add("GET", $v{r.path}, $handler);
											case "post": macro __autoRouter.add("POST", $v{r.path}, $handler);
											case "put": macro __autoRouter.add("PUT", $v{r.path}, $handler);
											case "delete": macro __autoRouter.add("DELETE", $v{r.path}, $handler);
											case "patch": macro __autoRouter.add("PATCH", $v{r.path}, $handler);
											default: null;
										};

										if (addRoute != null) {
											trace('[AutoRouter] REGISTERING ROUTE: ' + r.method.toUpperCase() + ' ' + r.path);
											routeExprs.push(addRoute);
										}
									}

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
