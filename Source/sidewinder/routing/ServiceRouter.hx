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
 *
 * TEST-DI-PARITY-S1 -- `route()` exists so DI registration and HTTP route generation can be
 * separated where a composition root needs one without the other.
 *
 * The motivating case: production and tests were maintaining two hand-written DI composition
 * roots, which silently drifted (56 production registrations absent from the effective test
 * graph, plus at least one LIFETIME mismatch that made a Singleton capture a Scoped service).
 * Fixing that by sharing one canonical DI registrar was blocked because 13 of the shared
 * services register through `register()`, which also emits an HTTP route -- and the test
 * composition root must not serve production routes. Splitting the two lets the shared registrar
 * own DI while production keeps its routes.
 *
 * `register()` is unchanged and remains the right call for anything that wants both.
 */
class ServiceRouter {

    #if macro
    /**
     * The route half, shared by both macros so there is exactly one implementation of it.
     * Compile-time only -- it builds an expression, it does not run at runtime.
     */
    static function buildRouteExpr(bootstrapExpr:Expr, ifaceExpr:Expr):Expr {
        return macro $bootstrapExpr._pendingRoutes.push(
            function(r:sidewinder.routing.Router, c:sidewinder.interfaces.ICacheService) {
                sidewinder.routing.AutoRouter.build(r, $ifaceExpr, () -> sidewinder.core.DI.get($ifaceExpr), c);
            });
    }
    #end

    /** DI registration + HTTP route. Behaviour unchanged; existing callers are unaffected. */
    public static macro function register(
        bootstrapExpr:Expr,
        servicesExpr:Expr,
        serviceTypeExpr:Expr,
        ifaceExpr:Expr,
        implExpr:Expr
    ):Expr {
        var routeExpr = buildRouteExpr(bootstrapExpr, ifaceExpr);
        return macro {
            $servicesExpr.addService($serviceTypeExpr, $ifaceExpr, $implExpr);
            $routeExpr;
        };
    }

    /**
     * HTTP route ONLY -- registers nothing in DI.
     *
     * For services whose DI registration comes from a shared registrar that both production and
     * tests consume: production calls this afterwards to add the route, tests do not, and the
     * service is registered exactly once either way.
     */
    public static macro function route(bootstrapExpr:Expr, ifaceExpr:Expr):Expr {
        return buildRouteExpr(bootstrapExpr, ifaceExpr);
    }
}
