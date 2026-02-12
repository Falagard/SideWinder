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
	// Global cookie jar shared by all async client instances
	public static var globalCookieJar:sidewinder.ICookieJar = new sidewinder.CookieJar();

	/**
	 * Recursively walk dynamic JSON value and convert date-like strings to Date instances.
	 * Supported patterns:
	 *  - ISO: YYYY-MM-DDTHH:mm:ss(.fraction)?(Z|±HH:MM)
	 *  - Space separated: YYYY-MM-DD HH:mm:ss(.fraction)?
	 *  - Date only: YYYY-MM-DD
	 */
	public static function normalizeDates(v:Dynamic):Dynamic {
		if (v == null)
			return v;
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = cast v;
			for (i in 0...arr.length)
				arr[i] = normalizeDates(arr[i]);
			return arr;
		}
		if (Reflect.isObject(v) && !Std.isOfType(v, String)) {
			for (f in Reflect.fields(v)) {
				Reflect.setField(v, f, normalizeDates(Reflect.field(v, f)));
			}
			return v;
		}
		if (Std.isOfType(v, String)) {
			var s:String = cast v;
			var isoDateTime = ~/^\d{4}-\d{2}-\d{2}(T| )(\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/;
			var isoDateOnly = ~/^\d{4}-\d{2}-\d{2}$/;
			if (isoDateTime.match(s) || isoDateOnly.match(s)) {
				try {
					return Date.fromString(s);
				} catch (e:Dynamic) {
					if (s.indexOf(' ') != -1) {
						var isoAttempt = StringTools.replace(s, ' ', 'T');
						try
							return Date.fromString(isoAttempt)
						catch (_:Dynamic) {}
					}
					return s;
				}
			}
			// Epoch milliseconds (13 digits)
			var epochMs = ~/^\d{13}$/;
			if (epochMs.match(s)) {
				var ms = Std.parseFloat(s);
				if (!Math.isNaN(ms))
					return Date.fromTime(ms);
			}
			return s;
		}
		return v;
	}

	public static macro function create(iface:Expr, baseUrl:Expr, ?cookieJar:Expr):Expr {
		var ifaceName = switch (iface.expr) {
			case EConst(CIdent(s)): s;
			default:
				Context.error("Expected interface identifier", iface.pos);
				"";
		};
		var t = Context.getType(ifaceName);
		switch (t) {
			case TInst(clRef, _):
				var cl = clRef.get();
				if (!cl.isInterface)
					Context.error(cl.name + " is not an interface", iface.pos);
				var uniqueName = cl.name + "_AutoClientAsync_" + Std.string(Std.random(999999));
				var fields:Array<Field> = [];
				// baseUrl field
				fields.push({
					name: "baseUrl",
					access: [APublic],
					kind: FVar(macro :String, null),
					pos: Context.currentPos()
				});
				// cookieJar field
				fields.push({
					name: "cookieJar",
					access: [APublic],
					kind: FVar(macro :sidewinder.ICookieJar, null),
					pos: Context.currentPos()
				});
				// constructor
				fields.push({
					name: "new",
					access: [APublic],
					kind: FFun({
						args: [
							{name: "baseUrl", type: macro :String},
							{name: "cookieJar", type: macro :sidewinder.ICookieJar}
						],
						expr: macro {
							this.baseUrl = baseUrl;
							this.cookieJar = cookieJar;
						},
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
							{name: "method", type: macro :String},
							{name: "path", type: macro :String},
							{name: "body", type: macro :Dynamic},
							{name: "onData", type: macro :String->Void},
							{name: "onError", type: macro :Dynamic->Void}
						],
						params: [],
						ret: macro :Void,
						expr: macro {
							trace('[AutoClientAsync] doRequestAsync begin method=' + method + ' path=' + path);
							var full = baseUrl + path;
							trace('[AutoClientAsync] full URL=' + full);
							var jsonBody = (body != null) ? haxe.Json.stringify(body) : null;
							if (jsonBody != null)
								trace('[AutoClientAsync] jsonBody=' + jsonBody);
							var h = new haxe.Http(full);
							h.setHeader("Accept", "application/json");
							if (jsonBody != null) {
								h.setHeader("Content-Type", "application/json");
								h.setPostData(jsonBody);
							}

							// Add cookies for sys targets
							// Add cookies for sys targets (excluding JS/HTML5 where browser handles it)
							#if (sys && !js && !html5)
							trace('[AutoClientAsync] Current cookies in jar: ' + cookieJar.getAllCookies().length);
							for (c in cookieJar.getAllCookies()) {
								trace('[AutoClientAsync]   Cookie: ' + c.toString());
							}
							var cookieHeader = cookieJar.getCookieHeader(full);
							if (cookieHeader != "") {
								h.setHeader("Cookie", cookieHeader);
								trace('[AutoClientAsync] Sending Cookie header: ' + cookieHeader);
							} else {
								trace('[AutoClientAsync] No matching cookies to send for URL: ' + full);
							}
							#end

							// Polyfill: Also set Authorization header if we have a session_token (ALL targets)
							if (cookieJar != null) {
								for (c in cookieJar.getAllCookies()) {
									if (c.name == "session_token") {
										h.setHeader("Authorization", "Bearer " + c.value);
										trace('[AutoClientAsync] Added Authorization header from session_token cookie');
									}
								}
							}

							h.onError = function(e:String) onError(e);

							// Store response headers callback for sys targets
							// Store response headers callback for sys targets (excluding JS/HTML5)
							#if (sys && !js && !html5)
							h.onStatus = function(status:Int) {
								trace('[AutoClientAsync] Response status: ' + status);
								try {
									// Prefer multiple header values (e.g. duplicate Set-Cookie)
									var handled = false;
									try {
										var setCookies:Array<String> = untyped h.getResponseHeaderValues("Set-Cookie");
										if (setCookies != null && setCookies.length > 0) {
											trace('[AutoClientAsync] Processing ' + setCookies.length + ' Set-Cookie headers...');
											for (sc in setCookies) {
												trace('[AutoClientAsync] Received Set-Cookie: ' + sc);
												cookieJar.setCookie(sc, full);
											}
											trace('[AutoClientAsync] Cookie stored. Total cookies now: ' + cookieJar.getAllCookies().length);
											handled = true;
										}
									} catch (_:Dynamic) {
										// Method not available on this target/version; fallback below
									}
									if (!handled) {
										// Fallback: legacy single-value map (may lose duplicates)
										var headers:haxe.ds.StringMap<String> = h.responseHeaders;
										if (headers != null) {
											trace('[AutoClientAsync] Fallback header map iteration...');
											for (key in headers.keys()) {
												if (key.toLowerCase() == "set-cookie") {
													var setCookieValue = headers.get(key);
													if (setCookieValue != null) {
														trace('[AutoClientAsync] Received Set-Cookie (map): ' + setCookieValue);
														cookieJar.setCookie(setCookieValue, full);
													}
												}
											}
											trace('[AutoClientAsync] Cookie stored. Total cookies now: ' + cookieJar.getAllCookies().length);
										} else {
											trace('[AutoClientAsync] No response headers available');
										}
									}
								} catch (e:Dynamic) {
									trace('[AutoClientAsync] Error parsing headers: ' + Std.string(e));
								}
							};
							#end

							// Use customRequest for verbs beyond GET/POST (PUT/DELETE) as per gist reference.
							if (method == "PUT" || method == "DELETE") {
								#if (js || html5)
								trace('[AutoClientAsync] using XMLHttpRequest for ' + method);
								var xhr = new js.html.XMLHttpRequest();
								xhr.open(method, full, true);
								// Allow cookies / auth headers cross-origin when server sets Access-Control-Allow-Credentials
								xhr.withCredentials = true;
								xhr.setRequestHeader("Accept", "application/json");
								if (jsonBody != null)
									xhr.setRequestHeader("Content-Type", "application/json");

								// Inject Authorization header from cookieJar
								if (cookieJar != null) {
									for (c in cookieJar.getAllCookies()) {
										if (c.name == "session_token") {
											xhr.setRequestHeader("Authorization", "Bearer " + c.value);
										}
									}
								}
								xhr.onreadystatechange = function() {
									if (xhr.readyState == 4) {
										if (xhr.status >= 200 && xhr.status < 300) {
											onData(xhr.responseText);
										} else {
											onError('HTTP ' + xhr.status + ' ' + xhr.statusText);
										}
									}
								};
								try {
									xhr.send(jsonBody != null ? jsonBody : null);
								} catch (e:Dynamic) {
									trace('[AutoClientAsync] XHR error ' + Std.string(e));
									onError(e);
								}
								#else
								trace('[AutoClientAsync] using customRequest for ' + method);
								var out = new haxe.io.BytesOutput();
								try {
									// post flag true if we have a body; method passed explicitly.
									trace('[AutoClientAsync] invoking customRequest postFlag=' + (jsonBody != null));
									h.customRequest(jsonBody != null, out, method);
									trace('[AutoClientAsync] customRequest returned bytes length=' + out.getBytes().length);
									var respStr = out.getBytes().toString();
									onData(respStr);
								} catch (e:Dynamic) {
									trace('[AutoClientAsync] customRequest error ' + Std.string(e));
									onError(e);
								}
								#end
							} else {
								// GET/POST handled by request; POST when body or explicit method
								h.onData = function(d:String) onData(d);
								trace('[AutoClientAsync] invoking request isPost=' + (method == "POST"));
								try
									h.request(method == "POST")
								catch (e:Dynamic)
									onError(e);
							}
							trace('[AutoClientAsync] doRequestAsync exit method=' + method + ' path=' + path);
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
							if (httpMethod == "" || path == "")
								continue; // skip unannotated
							switch (field.type) {
								case TFun(args, ret):
									var pathParamNames:Array<String> = [];
									for (segment in path.split("/"))
										if (StringTools.startsWith(segment, ":"))
											pathParamNames.push(segment.substr(1));
									var argDecls:Array<FunctionArg> = [];
									var renamed = new Map<String, String>();
									for (a in args) {
										// Skip userId parameter if @requiresAuth is set
										if (requiresAuth && a.name == "userId") {
											continue;
										}
										var newName = pathParamNames.indexOf(a.name) != -1 ? '_' + a.name : a.name;
										renamed.set(a.name, newName);
										argDecls.push({name: newName, type: Context.toComplexType(a.t)});
									}
									// Runtime URL building: start from literal path, replace :param tokens using renamed args
									var bodyExprs:Array<Expr> = [];
									bodyExprs.push(macro var _p = $v{path});
									for (pp in pathParamNames) {
										var renamedIdent = renamed.get(pp);
										var identExpr:Expr = {expr: EConst(CIdent(renamedIdent)), pos: Context.currentPos()};
										bodyExprs.push(macro _p = StringTools.replace(_p, ":" + $v{pp}, Std.string($identExpr)));
									}
									// Determine body arg (first non-path param for POST/PUT)
									var bodyArg:Null<String> = null;
									if (httpMethod == "POST" || httpMethod == "PUT") {
										for (a in args)
											if (pathParamNames.indexOf(a.name) == -1) {
												bodyArg = renamed.get(a.name);
												break;
											}
									}
									var bodyExpr:Expr = (bodyArg != null) ? macro $i{bodyArg} : macro null;
									var followedRet = Context.follow(ret);
									var retName = TypeTools.toString(followedRet);
									// Add async callback args
									// Special case void return: callback takes no parameters
									var voidType:ComplexType = TPath({pack: [], name: "Void", params: []});
									if (retName == "Void") {
										argDecls.push({name: "onSuccess", type: TFunction([], voidType)});
									} else {
										argDecls.push({name: "onSuccess", type: TFunction([Context.toComplexType(ret)], voidType)});
									}
									argDecls.push({name: "onFailure", type: macro :Dynamic->Void});
									var parseExpr:Expr;
									if (retName == "Void") {
										parseExpr = macro {trace('[AutoClientAsync] parse void response'); onSuccess();};
									} else if (retName == "Int") {
										parseExpr = macro {
											trace('[AutoClientAsync] parse Int raw=' + d);
											var parsed = Std.parseInt(d);
											onSuccess(parsed == null ? 0 : parsed);
										};
									} else if (retName == "Float") {
										parseExpr = macro {trace('[AutoClientAsync] parse Float raw=' + d); onSuccess(Std.parseFloat(d));};
									} else if (retName == "Bool") {
										parseExpr = macro {
											var s = d;
											trace('[AutoClientAsync] parse Bool raw=' + s);
											onSuccess(s == "true" || s == "1");
										};
									} else if (retName == "String") {
										parseExpr = macro {trace('[AutoClientAsync] pass String raw length=' + (d == null ? 0 : d.length)); onSuccess(d);};
									} else {
										parseExpr = macro {
											if (d == null || d == "") {
												trace('[AutoClientAsync] empty JSON body');
												onSuccess(null);
											} else {
												try {
													trace('[AutoClientAsync] parsing JSON length=' + d.length);
													var raw = haxe.Json.parse(d);
													var converted = sidewinder.AutoClientAsync.normalizeDates(raw);
													onSuccess(converted);
												} catch (e:Dynamic) {
													trace('[AutoClientAsync] JSON parse error ' + Std.string(e));
													onFailure(e);
												}
											}
										};
									}
									bodyExprs.push(macro doRequestAsync($v{httpMethod}, _p, $bodyExpr, function(d:String) $parseExpr,
										function(e:Dynamic) onFailure(e)));
									var methodBody:Expr = {expr: EBlock(bodyExprs), pos: Context.currentPos()};
									fields.push({
										name: field.name + "Async",
										access: [APublic],
										kind: FFun({
											args: argDecls,
											params: [],
											ret: macro :Void,
											expr: methodBody
										}),
										pos: field.pos
									});
								default:
							}
						default:
					}
				}
				var ifaceTypePath:TypePath = {pack: cl.pack, name: cl.name};
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
				var typePath:TypePath = {pack: ["sidewinder"], name: uniqueName};
				// If cookieJar parameter was provided, use it; otherwise use globalCookieJar
				var jarExpr = cookieJar != null ? cookieJar : macro sidewinder.AutoClientAsync.globalCookieJar;
				return {expr: ENew(typePath, [baseUrl, jarExpr]), pos: Context.currentPos()};
			case _:
				Context.error("Expected interface type", iface.pos);
				return macro null;
		}
	}
}
