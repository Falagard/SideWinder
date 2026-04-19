package sidewinder.client;

#if (macro || display)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end
import haxe.io.BytesOutput;

#if (macro || display)
using haxe.macro.TypeTools;
using haxe.macro.ExprTools;
#end

/**
 * Auth modes supported by AutoClient.
 */
enum AutoClientAuthMode {
    None;
    ProjectSession;
    NodeSession;
    ControlPlaneService;
}

/**
 * Result of an auth preparation or refresh operation.
 */
enum AutoClientAuthResult {
    Success;
    Failure(error:Dynamic);
}

/**
 * Metadata for a pending request.
 */
typedef AutoClientRequest = {
    var method:String;
    var url:String;
    var headers:Map<String,String>;
    var body:Null<String>;
    var authMode:AutoClientAuthMode;
}

/**
 * Interface for pluggable auth providers.
 * Providers handle token management, concurrency, and refresh logic.
 */
interface IAutoClientAuthProvider {
    function prepareRequestAuth(request:AutoClientRequest, done:AutoClientAuthResult->Void):Void;
    function refreshRequestAuth(request:AutoClientRequest, done:AutoClientAuthResult->Void):Void;
}

/**
 * Registry to resolve auth providers based on auth mode.
 */
interface IAutoClientAuthProviderResolver {
    function resolve(authMode:AutoClientAuthMode):Null<IAutoClientAuthProvider>;
}

/**
 * Options for creating an AutoClient instance.
 */
typedef AutoClientOptions = {
    var baseUrl:String;
    @:optional var cookieJar:Dynamic;
    @:optional var projectKey:String;
    @:optional var token:String;
    @:optional var authProviderResolver:IAutoClientAuthProviderResolver;
}

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
		var options = macro {
			baseUrl: $baseUrl,
			cookieJar: $cookieJar,
			projectKey: $apiKey,
			token: $token,
			authProviderResolver: null
		};
		return _generateClient(iface, options);
	}

	public static macro function createWithOptions(iface:Expr, options:Expr):Expr {
		return _generateClient(iface, options);
	}

	#if (macro || display)
	private static function _generateClient(iface:Expr, optionsExpr:Expr):Expr {
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
				
				// options field
				fields.push({
					name: "options",
					access: [APublic],
					kind: FVar(macro :sidewinder.client.AutoClientAsync.AutoClientOptions, null),
					pos: Context.currentPos()
				});
				
				// constructor
				fields.push({
					name: "new",
					access: [APublic],
					kind: FFun({
						args: [
							{name: "options", type: macro :sidewinder.client.AutoClientAsync.AutoClientOptions}
						],
						expr: macro {
							this.options = options;
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
							{name: "authMode", type: macro :sidewinder.client.AutoClientAsync.AutoClientAuthMode},
							{name: "onData", type: macro :String->Void},
							{name: "onError", type: macro :Dynamic->Void}
						],
						params: [],
						ret: macro :Void,
						expr: macro {
							var request:sidewinder.client.AutoClientAsync.AutoClientRequest = {
								method: method,
								url: options.baseUrl + path,
								headers: new Map<String, String>(),
								body: (body != null) ? haxe.Json.stringify(body) : null,
								authMode: authMode
							};
							
							var retryAttempted = false;
							var executeHttp:Void->Void = null;
							executeHttp = function() {
								trace('[AutoClientAsync] request method=' + request.method + ' url=' + request.url);
								
								var h = new haxe.Http(request.url);
								h.setHeader("Accept", "application/json");
								if (request.body != null) {
									h.setHeader("Content-Type", "application/json");
									h.setPostData(request.body);
								}
								
								if (options.projectKey != null && options.projectKey != "") {
									h.setHeader("X-Project-Key", options.projectKey);
								}
								
								// Apply external headers from request.headers
								for (key in request.headers.keys()) {
									h.setHeader(key, request.headers.get(key));
								}
								
								if (options.token != null && options.token != "" && !request.headers.exists("Authorization")) {
									h.setHeader("Authorization", "Bearer " + options.token);
								}
								
								#if (sys && !js && !html5)
								var cookieJar:sidewinder.interfaces.ICookieJar = options.cookieJar;
								if (cookieJar != null) {
									var cookieHeader = cookieJar.getCookieHeader(request.url);
									if (cookieHeader != "") h.setHeader("Cookie", cookieHeader);
									if (!request.headers.exists("Authorization")) {
										for (c in cookieJar.getAllCookies()) {
											if (c.name == "platform_session_token" || c.name == "session_token") {
												h.setHeader("Authorization", "Bearer " + c.value);
												break;
											}
										}
									}
								}
								#end

								var status = 0;
								h.onStatus = function(s:Int) status = s;
								
								h.onData = function(rawData:String) {
									if (status == 401 && !retryAttempted && authMode != None && options.authProviderResolver != null) {
										var provider = options.authProviderResolver.resolve(authMode);
										if (provider != null) {
											retryAttempted = true;
											trace('[AutoClientAsync] 401 Unauthorized (data), attempting refresh...');
											provider.refreshRequestAuth(request, function(result) {
												switch (result) {
													case Success:
														executeHttp();
													case Failure(err):
														onError(err);
												}
											});
											return;
										}
									}
									onData(rawData);
								};
								
								h.onError = function(err:Dynamic) {
									if (status == 401 && !retryAttempted && authMode != None && options.authProviderResolver != null) {
										var provider = options.authProviderResolver.resolve(authMode);
										if (provider != null) {
											retryAttempted = true;
											trace('[AutoClientAsync] 401 Unauthorized (error), attempting refresh...');
											provider.refreshRequestAuth(request, function(result) {
												switch (result) {
													case Success:
														executeHttp();
													case Failure(err):
														onError(err);
												}
											});
											return;
										}
									}
									onError(err);
								};
								
								try {
									h.request(request.method == "POST");
								} catch (e:Dynamic) {
									onError(e);
								}
							};

							// Handle initial auth preparation
							if (authMode != None && options.authProviderResolver != null) {
								var provider = options.authProviderResolver.resolve(authMode);
								if (provider != null) {
									provider.prepareRequestAuth(request, function(result) {
										switch (result) {
											case Success:
												executeHttp();
											case Failure(err):
												onError(err);
										}
									});
									return;
								}
							}
							
							executeHttp();
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
							var authModeExpr = macro sidewinder.client.AutoClientAsync.AutoClientAuthMode.None;
							
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
										authModeExpr = macro sidewinder.client.AutoClientAsync.AutoClientAuthMode.ProjectSession;
									case "auth":
										if (m.params.length > 0) {
											var p = m.params[0];
											switch (p.expr) {
												case EConst(CIdent(s)):
													authModeExpr = macro sidewinder.client.AutoClientAsync.AutoClientAuthMode.$s;
												default: Context.error("Expected identifier in @auth", p.pos);
											}
										}
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
									bodyExprs.push(macro doRequestAsync($v{httpMethod}, _p, $bodyExpr, $authModeExpr, function(rawData:String) $parseExpr,
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
				return {expr: ENew(typePath, [optionsExpr]), pos: Context.currentPos()};
			case _:
				Context.error("Expected interface type", iface.pos);
				return macro null;
		}
	}
	#end
}
