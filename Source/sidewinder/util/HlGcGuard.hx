package sidewinder.util;

#if hl
/**
 * Thin delegating wrapper around the shared `hlgcguard.HlGcGuard` (see
 * https://github.com/Falagard/hl-gc-guard, package `hlgcguard`).
 *
 * `hl.Gc.enable(bool)` sets a single, process-global, non-reentrant flag with no getter
 * (`gc_is_active` in HashLink's own `src/gc.c`). This class used to maintain its OWN
 * mutex-protected depth counter, entirely independent from the structurally identical copies
 * that accumulated in `hx.injection.HlGcGuard` (haxe-injection fork) and hxwell's own copy.
 * Two *different* counters don't know about each other, so whenever two of them were
 * concurrently active in the same process (SideWinder DB work overlapping a DI resolution, or
 * hxwell's TemplateData static-init overlapping either), the exact cross-boundary version of
 * the race this pattern exists to prevent could still happen: whichever guard's counter hit
 * zero first would call `hl.Gc.enable(true)`, re-enabling the GC globally while the OTHER
 * guard's caller was still mid-allocation under the assumption it was still protected.
 *
 * Fixed (HLC-BOOT-MIGRATION-GC-SIGSEGV-S1) by extracting the counter itself into a standalone,
 * zero-dependency package (`hl-gc-guard`) that every one of these libraries now delegates to,
 * so there is exactly one depth counter per process. Every existing call site in this repo
 * (`sidewinder.util.HlGcGuard.disable()`/`.restore()`, ~65+ files) keeps working unchanged --
 * only this class's own implementation changed.
 */
class HlGcGuard {
    public static inline function disable():Void {
        hlgcguard.HlGcGuard.disable();
    }

    public static inline function restore():Void {
        hlgcguard.HlGcGuard.restore();
    }
}
#end
