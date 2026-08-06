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
	/** Sentinel returned by the no-op stub below (not a real "fds marked" count) --
	    callers MUST check for this before treating the return value as a success count. */
	public static inline var NOT_APPLIED:Int = -1;

	#if sidewinder_fdutil
	@:hlNative("fdutil", "set_cloexec_on_open_fds")
	public static function setCloexecOnOpenFds(minFd:Int):Int {
		return 0;
	}
	#else
	/** No-op stub: gated behind the `sidewinder_fdutil` CAPABILITY define, not a host-OS
	    define like `#if mac`. This is deliberate -- `mac`/`windows`/`linux` are only
	    auto-defined by lime's own build-tool invocation (`lime build hl` / `lime test`
	    inject them into the generated compiler args), NOT by plain `haxe some.hxml`
	    compiles. `Server/headless.hxml` -- the actual production companion build, the
	    exact artifact FootNoteStudio's companion launcher spawns -- is a plain `haxe`
	    compile with no lime build-tool driver involved, so it never gets `-D mac` even
	    on a real macOS machine. Gating on `#if mac` here previously meant the FD_CLOEXEC
	    fix silently compiled to a no-op on the one build target it most needed to apply
	    to -- no compile error, no crash, just silently unfixed. `sidewinder_fdutil` is
	    instead an explicit, positive "this build ships a matching fdutil.hdll for its
	    platform" declaration that each consuming .hxml/project.xml must opt into
	    directly (see Server/headless.hxml, Server/build.hxml, Server/project.xml,
	    Server/tests.xml) -- so the define's presence is always traceable to an explicit
	    line in a build config, never to lime's implicit host-OS autodef.

	    fdutil.hdll is currently only built for macOS. Windows/Linux native builds of the
	    FD_CLOEXEC fix are a real, tracked follow-up -- not silently dropped, just not
	    buildable in this dev environment (macOS only, no cross-compilation toolchain
	    available). Referencing the native symbol unconditionally here would be a fatal
	    HL module-load failure on platforms without a matching .hdll (confirmed
	    empirically: HashLink resolves @:hlNative bindings eagerly at module load, before
	    any Haxe try/catch can run) -- so this MUST stay a genuine no-op, not a
	    @:hlNative declaration, on any build that does not explicitly pass
	    `-D sidewinder_fdutil`. Returns NOT_APPLIED (-1); callers must check for this and
	    log accordingly rather than treating it as a real "fds marked" count. */
	public static function setCloexecOnOpenFds(minFd:Int):Int {
		return NOT_APPLIED;
	}
	#end
}
#end
