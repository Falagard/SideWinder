package;

import haxe.macro.Expr;
import haxe.macro.Context;

/**
 * Compile-time route generator.
 */
class AutoRouter {
	/**
	 * Build routes from annotated interfaces and implementation instances.
	 * 
	 * Example:
	 * AutoRouter.build(router, [
	 *   { iface: IUserService, impl: new UserService() }
	 * ]);
	 */
	macro public static function build(routerExpr:Expr, services:Array<Expr>):Expr {
		var router = routerExpr;
		var routeExprs:Array<Expr> = [];

		for (entry in services) {
			switch entry.expr {
				case EObjectDecl(fields):
					var ifaceExpr:Expr = null;
					var implExpr:Expr = null;
					for (f in fields) {
						switch (f.field) {
							case "iface": ifaceExpr = f.expr;
							case "impl": implExpr = f.expr;
						}
					}
					if (ifaceExpr == null || implExpr == null)
						Context.error("Expected { iface: ..., impl: ... } object", entry.pos);

					// Extract interface definition
                    var ifaceType = Context.follow(Context.typeof(ifaceExpr));
                    var td = switch ifaceType {
                        case TType(t, _): t; // Use t directly, not t.get()
                        default: Context.error("Expected interface type", entry.pos);
                    };

                    

                    //td.get().


					// // Generate routes from each annotated method
					// for (field in (td.fields : Array<Field>)) { // Cast to Array<Field>
					// 	var method = "";
                    //     var path = "";
                    //     for (m in (field.meta : Array<MetaData>)) { // Cast to Array<MetaData>
                    //         switch (m.name) {
                    //             case "get", "post", "put", "delete":
                    //                 method = m.name;
                    //                 if (m.params.length > 0) path = Std.string(m.params[0]); // Use Std.string or Context.evalExpr
                    //             default:
                    //         }
                    //     }
                    //     if (method == "" || path == "")
                    //         continue;

					// 	var argNames = [for (a in (field.args : Array<FunctionArg>)) a.name]; // Cast to Array<FunctionArg>
                    //     var callArgs = [for (a in argNames) macro req.params.get($v{a})];

                    //     var handler = macro(req, res) -> {
                    //         var result = $implExpr.$field.name($a{callArgs});
                    //         if (result != null)
                    //             res.write(haxe.Json.stringify(result));
                    //         res.end();
                    //     };

					// 	var addRoute = switch method {
					// 		case "get": macro $router.get($v{path}, $handler);
					// 		case "post": macro $router.post($v{path}, $handler);
					// 		case "put": macro $router.put($v{path}, $handler);
					// 		case "delete": macro $router.delete($v{path}, $handler);
					// 		default: null;
					// 	};

					// 	if (addRoute != null)
					// 		routeExprs.push(addRoute);
					// }

				default:
                    continue;
					//Context.error("Expected an array of objects like { iface: ..., impl: ... }", entry.pos);
			}
		}

		return macro {
			$b{routeExprs};
		};
	}
}
