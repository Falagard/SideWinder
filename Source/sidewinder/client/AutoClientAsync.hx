package sidewinder.client;

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
	public static var globalCookieJar:sidewinder.interfaces.ICookieJar = new sidewinder.data.CookieJar();

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

	public static macro function create(iface:Expr, baseUrl:Expr, ?cookieJar:Expr, ?apiKey:Expr, ?token:Expr):Expr {
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
					kind: FVar(macro :sidewinder.interfaces.ICookieJar, null),
					pos: Context.currentPos()
				});
				// apiKey field
				fields.push({
					name: "apiKey",
					access: [APublic],
					kind: FVar(macro :String, null),
					pos: Context.currentPos()
				});
				// token field (for Bearer Auth)
				fields.push({
					name: "token",
					access: [APublic],
					kind: FVar(macro :String, null),
					pos: Context.currentPos()
				});
				// constructor
				fields.push({
					name: "new",
					access: [APublic],
					kind: FFun({
						args: [
							{name: "baseUrl", type: macro :String},
							{name: "cookieJar", type: macro :sidewinder.interfaces.ICookieJar},
							{name: "apiKey", type: macro :String},
							{name: "token", type: macro :String}
						],
						expr: macro {
							this.baseUrl = baseUrl;
							this.cookieJar = cookieJar;
							this.apiKey = apiKey;
							this.token = token;
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
							var isPost = method == "POST";
							var maxRedirects = 5;
							var redirectCount = 0;
							var currentFull = full;

							var executeRequest:Void->Void = null;
							executeRequest = function() {
								var h = new haxe.Http(currentFull);
								h.setHeader("Accept", "application/json");
								if (jsonBody != null) {
									h.setHeader("Content-Type", "application/json");
									h.setPostData(jsonBody);
								}
								if (apiKey != null && apiKey != "") {
									h.setHeader("X-Project-Key", apiKey);
								}
								if (token != null && token != "") {
									h.setHeader("Authorization", "Bearer " + token);
								}
								#if (sys && !js && !html5)
								var cookieHeader = cookieJar.getCookieHeader(currentFull);
								if (cookieHeader != "") h.setHeader("Cookie", cookieHeader);
								if (token == null || token == "") {
									for (c in cookieJar.getAllCookies()) {
										if (c.name == "platform_session_token" || c.name == "session_token") {
											h.setHeader("Authorization", "Bearer " + c.value);
											break;
										}
									}
								}
								#end
								// Capture redirect location from response headers after request completes
								var redirectLocation:String = null;
								h.onStatus = function(status:Int) {
									if ((status == 301 || status == 302 || status == 307 || status == 308) && redirectCount < maxRedirects) {
										var loc = h.responseHeaders.get("Location");
										if (loc != null && loc != "") {
											if (loc.indexOf("://") == -1) {
												var base = currentFull.split("/").slice(0, 3).join("/");
												loc = base + loc;
											}
											redirectLocation = loc;
										}
									}
								};
								h.onData = function(d:Dynamic) {
									if (redirectLocation != null) {
										// Redirect: fire next request after this response is done
										redirectCount++;
										currentFull = redirectLocation;
										redirectLocation = null;
										trace('[AutoClientAsync] Following redirect to: ' + currentFull);
										executeRequest();
										return;
									}
									// Use Std.string which safely handles hl.Bytes on HashLink
									onData(Std.string(d));
								};
								h.onError = function(e:Dynamic) {
									if (redirectLocation != null) {
										redirectCount++;
										currentFull = redirectLocation;
										redirectLocation = null;
										trace('[AutoClientAsync] Following redirect (via error) to: ' + currentFull);
										executeRequest();
										return;
									}
									onError(e);
								};
								try {
									h.request(isPost);
								} catch (e:Dynamic) {
									onError(e);
								}
							};
							executeRequest();
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
										if (StringTools.startsWith(segment, ":")) {
											var paramName = segment.substr(1);
											// Strip * prefix for catch-all params (e.g. :*slug -> slug)
											if (StringTools.startsWith(paramName, "*"))
												paramName = paramName.substr(1);
											pathParamNames.push(paramName);
										}
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
										bodyExprs.push(macro _p = StringTools.replace(_p, ":*" + $v{pp}, Std.string($identExpr)));
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

									// Determine query params (args that are not path params and not the body arg)
									for (a in args) {
										if (pathParamNames.indexOf(a.name) == -1) {
											var renamedIdent = renamed.get(a.name);
											if (httpMethod != "GET" && (bodyArg == renamedIdent))
												continue;
											if (requiresAuth && a.name == "userId")
												continue;

											var identExpr:Expr = {expr: EConst(CIdent(renamedIdent)), pos: Context.currentPos()};
											bodyExprs.push(macro {
												var __v:Dynamic = $identExpr;
												if (__v != null) {
													_p += (_p.indexOf("?") == -1 ? "?" : "&") + $v{a.name} + "=" + StringTools.urlEncode(Std.string(__v));
												}
											});
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
											trace('[AutoClientAsync] parse Int raw=' + rawData);
											var parsed = Std.parseInt(rawData);
											onSuccess(parsed == null ? 0 : parsed);
										};
									} else if (retName == "Float") {
										parseExpr = macro {trace('[AutoClientAsync] parse Float raw=' + rawData); onSuccess(Std.parseFloat(rawData));};
									} else if (retName == "Bool") {
										parseExpr = macro {
											var s = rawData;
											trace('[AutoClientAsync] parse Bool raw=' + s);
											if (s == "true" || s == "1") {
												onSuccess(true);
											} else if (s == "false" || s == "0" || s == null || s == "") {
												onSuccess(false);
											} else {
												try {
													var json = haxe.Json.parse(s);
													if (Reflect.hasField(json, "success")) {
														onSuccess(Reflect.field(json, "success"));
													} else {
														onSuccess(false);
													}
												} catch (e:Dynamic) {
													onSuccess(false);
												}
											}
										};
									} else if (retName == "String") {
										parseExpr = macro {trace('[AutoClientAsync] pass String raw length=' + (rawData == null ? 0 : rawData.length)); onSuccess(rawData);};
									} else {
										parseExpr = macro {
											if (rawData == null || rawData == "") {
												trace('[AutoClientAsync] empty JSON body');
												onSuccess(null);
											} else {
												try {
													trace('[AutoClientAsync] parsing JSON length=' + rawData.length);
													var raw = haxe.Json.parse(rawData);
													var converted = sidewinder.client.AutoClientAsync.normalizeDates(raw);
													
													// HashLink specific: verify array return if expected
													var isArr = $v{StringTools.startsWith(retName, "Array<")};
													if (isArr && converted != null && !Std.isOfType(converted, Array)) {
														trace('[AutoClientAsync] Expected array but got object, likely error response or login required');
														onFailure(Std.string(converted));
													} else {
														try {
															// Use untyped to avoid HashLink strict cast issues at the call site
															untyped onSuccess(converted);
														} catch (err:Dynamic) {
															trace('[AutoClientAsync] callback error ' + Std.string(err));
															onFailure(Std.string(err));
														}
													}
												} catch (e:Dynamic) {
													trace('[AutoClientAsync] JSON parse error ' + Std.string(e));
													onFailure(Std.string(e));
												}
											}
										};
									}
									bodyExprs.push(macro doRequestAsync($v{httpMethod}, _p, $bodyExpr, function(rawData:String) $parseExpr,
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
				var uniqueClassName = uniqueName;
				var classDef:TypeDefinition = {
					pack: ["sidewinder"],
					name: uniqueClassName,
					pos: Context.currentPos(),
					meta: [],
					params: [],
					isExtern: false,
					kind: TDClass(null, [], false),
					fields: fields
				};
				Context.defineType(classDef);
				var typePath:TypePath = {pack: ["sidewinder"], name: uniqueClassName};
				var jarExpr = cookieJar != null ? cookieJar : macro sidewinder.client.AutoClientAsync.globalCookieJar;
				var apiKeyExpr = apiKey != null ? apiKey : macro null;
				var tokenExpr = token != null ? token : macro null;
				return {expr: ENew(typePath, [baseUrl, jarExpr, apiKeyExpr, tokenExpr]), pos: Context.currentPos()};
			case _:
				Context.error("Expected interface type", iface.pos);
				return macro null;
		}
	}
}
