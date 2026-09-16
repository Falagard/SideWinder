package sidewinder.util;

#if hl
/**
 * `hl.Gc.enable(bool)` sets a single process-global flag (`gc_is_active` in HashLink's
 * src/gc.c) with no reentrancy, no thread-local scoping, and no getter. Any two call sites
 * that each do their own "disable, do risky allocation, re-enable" span will stomp on each
 * other the moment they nest OR run concurrently on different threads: whichever one finishes
 * first calls `hl.Gc.enable(true)` and re-enables the GC globally, even while another thread
 * (or an outer caller on the same thread) is still mid-way through an allocation it believed
 * was protected.
 *
 * This is a real, evidenced bug: SqliteApplicationDataRelocationRepository.readRows() disables
 * the GC, calls into SqliteDatabaseService.request(), which constructs a StaticResultSet whose
 * constructor did its own disable/iterate/unconditional-enable -- re-enabling the GC globally
 * before control returned to the outer caller's still-executing drain loop.
 *
 * Fix: route every disable/restore through this counted, mutex-protected guard instead of
 * calling hl.Gc.enable directly. The GC is only actually turned off on the transition into the
 * first concurrently-held guard, and only turned back on when the last holder (across every
 * thread) releases it.
 */
class HlGcGuard {
    static var _mutex = new sys.thread.Mutex();
    static var _depth:Int = 0;

    public static function disable():Void {
        _mutex.acquire();
        _depth++;
        if (_depth == 1) hl.Gc.enable(false);
        _mutex.release();
    }

    public static function restore():Void {
        _mutex.acquire();
        if (_depth > 0) _depth--;
        if (_depth == 0) hl.Gc.enable(true);
        _mutex.release();
    }
}
#end
