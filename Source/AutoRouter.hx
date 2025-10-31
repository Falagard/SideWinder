

package;

import haxe.macro.Expr;
import haxe.macro.Context;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

/**
 * Compile-time route generator.
 */
class AutoRouter {

	public static macro function build(routerExpr:Expr, ifaceExpr:Expr, implExpr:Expr):Expr {

		var router = routerExpr;
		var routeExprs:Array<Expr> = [];

        trace('Generating routes for ' + ifaceExpr.toString());

        // Evaluate the expression to a type
        var type = Context.getType(ifaceExpr.toString());
    
        // Ensure it’s an interface
        switch (type) {
            case TInst(t, _):
                var cl = t.get();
                if (!cl.isInterface) {
                    Context.error('${cl.name} is not an interface', ifaceExpr.pos);
                }

                // Iterate through all fields
                for (field in cl.fields.get()) {
                    switch (field.kind) {
                        case FMethod(_):
                            var method = "";
                            var path = "";
                            
                            for (m in field.meta.get()) { 
                                switch (m.name) {
                                    
                                    case "get", "post", "put", "delete":
                                        method = m.name;

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
                            trace('Method: ' + method + ", Path: " + path);

                            if (method == "" || path == "")
                                continue;

                            // field.type should be TFun for methods
                            switch (field.type) {
                                case TFun(args, ret):
                                    for (arg in args) {
                                        var typeStr = TypeTools.toString(arg.t);
                                        trace('  Arg: ' + arg.name + ' : ' + typeStr + (arg.opt ? " (optional)" : ""));
                                    }

                                    //implExpr is a function that returns an instance of something that derives from the interface ifaceExpr 
                                    //write macro that calls implExpr to get instance
                                    //create a handler that calls appropriate method on instance, then calls router.add(method, path, handler)

                                    trace('  Returns: ' + TypeTools.toString(ret));

                                default:
                                    Context.error('Unexpected non-function type on method', field.pos);
                            }

                        default:
                            // Skip vars or other field kinds
                    }
                }

            default:
                Context.error('Expected an interface type, got ' + TypeTools.toString(type), ifaceExpr.pos);
        }



        

        // // Extract interface definition
        // var ifaceType = Context.follow(Context.typeof(ifaceExpr));
        // var td = switch ifaceType {
        //     case TType(t, _): t; // Use t directly, not t.get()
        //     default: Context.error("Expected interface type", entry.pos);
        // };

		// for (entry in services) {
		// 	switch entry.expr {
		// 		case EObjectDecl(fields):

        // 			trace("EObjectDecl");

		// 			var ifaceExpr:Expr = null;
		// 			var implExpr:Expr = null;
		// 			for (f in fields) {
		// 				switch (f.field) {
		// 					case "iface": ifaceExpr = f.expr;
		// 					case "impl": implExpr = f.expr;
		// 				}
		// 			}
		// 			if (ifaceExpr == null || implExpr == null)
		// 				Context.error("Expected { iface: ..., impl: ... } object", entry.pos);

        //             trace('Generating routes for ' + ifaceExpr.toString());

		// 			// Extract interface definition
        //             var ifaceType = Context.follow(Context.typeof(ifaceExpr));
        //             var td = switch ifaceType {
        //                 case TType(t, _): t; // Use t directly, not t.get()
        //                 default: Context.error("Expected interface type", entry.pos);
        //             };

                    

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

		// 		default:
        //             continue;
		// 			//Context.error("Expected an array of objects like { iface: ..., impl: ... }", entry.pos);
		// 	}
		// }

		return macro {
			$b{routeExprs};
		};
	}
}

