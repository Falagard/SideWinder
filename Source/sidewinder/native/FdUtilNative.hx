package sidewinder.native;

/**
 * HashLink native bindings for fdutil (FOOTNOTE-MEDIA-WORKER-S1 Task 11,
 * Failure B fix — companion listener socket inherited by every spawned
 * child process because HashLink's std sys.net.Socket is never marked
 * FD_CLOEXEC).
 *
 * See the consuming project's `native/fdutil/fdutil_hl.c` for the full
 * root-cause writeup and implementation. This class only declares the
 * binding; the actual `fdutil.hdll` is built and shipped by the consuming
 * project (mirrors how `sidewinder.native.CivetWebNative` declares bindings
 * for a `civetweb.hdll` built elsewhere).
 *
 * Deliberately kept inside SideWinder (not the consuming app's own
 * namespace) because this fixes a defect in SideWinder's own HTTP listener
 * bring-up (see HxWellAdapter.start()'s onStart hook) — every server built
 * on this framework gets the fix, not just one consuming app.
 */
#if (hl && !macro)
class FdUtilNative {
	@:hlNative("fdutil", "set_cloexec_on_open_fds")
	public static function setCloexecOnOpenFds(minFd:Int):Int {
		return 0;
	}
}
#end
