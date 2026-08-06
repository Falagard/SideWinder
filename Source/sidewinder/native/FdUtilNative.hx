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
	#if mac
	@:hlNative("fdutil", "set_cloexec_on_open_fds")
	public static function setCloexecOnOpenFds(minFd:Int):Int {
		return 0;
	}
	#else
	/** No-op stub: fdutil.hdll is currently only built for macOS. Windows/Linux native
	    builds of the FD_CLOEXEC fix are a real, tracked follow-up -- not silently dropped,
	    just not buildable in this dev environment (macOS only, no cross-compilation
	    toolchain available). Referencing the native symbol unconditionally here would be a
	    fatal HL module-load failure on those platforms (confirmed empirically: HashLink
	    resolves @:hlNative bindings eagerly at module load, before any Haxe try/catch can
	    run) -- so this MUST stay a genuine no-op, not a @:hlNative declaration, until real
	    Windows/Linux fdutil.hdll builds exist. */
	public static function setCloexecOnOpenFds(minFd:Int):Int {
		return -1;
	}
	#end
}
#end
