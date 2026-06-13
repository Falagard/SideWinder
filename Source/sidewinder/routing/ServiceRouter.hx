package sidewinder.routing;

#if macro
import haxe.macro.Expr;
#end

/**
 * Eliminates the two-step footgun of addService() + AutoRouter.build().
 *
 * Usage in configureServices():
 *   ServiceRouter.register(this, services, ServiceType.Scoped, IFoo, FooImpl);
 *
 * This registers the service in DI and defers AutoRouter route building until
 * ServerBootstrap.init() calls flushPendingRoutes(router, cache) after
 * configureRoutes() completes.
 */
class ServiceRouter {
    public static macro function register(
        bootstrapExpr:Expr,
        servicesExpr:Expr,
        serviceTypeExpr:Expr,
        ifaceExpr:Expr,
        implExpr:Expr
    ):Expr {
        return macro {
            $servicesExpr.addService($serviceTypeExpr, $ifaceExpr, $implExpr);
            $bootstrapExpr._pendingRoutes.push(function(r:sidewinder.routing.Router, c:sidewinder.interfaces.ICacheService) {
                sidewinder.routing.AutoRouter.build(r, $ifaceExpr, () -> sidewinder.core.DI.get($ifaceExpr), c);
            });
        };
    }
}
