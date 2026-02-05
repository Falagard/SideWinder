# Building civetweb.hdll for HashLink (Windows)

This guide documents how to build the `civetweb.hdll` native library for HashLink on **Windows**. This library provides HashLink bindings for the CivetWeb embedded web server, enabling HTTP and WebSocket functionality in the SideWinder project.

> [!NOTE]
> **Building on Linux?** See [CIVETWEB_BUILD_GUIDE_LINUX.md](file:///c:/Src/ge/SideWinder/CIVETWEB_BUILD_GUIDE_LINUX.md) for Linux-specific instructions.

## Overview

The build process compiles CivetWeb's C source code along with custom HashLink bindings into a native `.hdll` (HashLink Dynamic Link Library) that can be loaded by HashLink applications.

**Build Output**: `civetweb.hdll` (Windows 64-bit DLL)

**Location**: [native/civetweb/hl/](file:///c:/Src/ge/SideWinder/native/civetweb/hl/)

---

## Prerequisites

### Required Software

1. **Visual Studio 2017 or later**
   - Required for the MSVC compiler (`cl.exe`) and linker (`link.exe`)
   - Community Edition is sufficient
   - Must include C/C++ development tools

2. **HashLink**
   - Typically installed via Lime: `C:\HaxeToolkit\haxe\lib\lime\8,2,2\templates\bin\hl`
   - Must include:
     - `include\hl.h` - HashLink C API headers
     - `libhl.lib` - HashLink import library (in root directory for standalone releases, or `Windows64\libhl.lib` for Lime's HashLink)

3. **Environment Setup**
   - The build script automatically locates Visual Studio using `vswhere.exe`
   - The `HASHLINK_PATH` environment variable is optional (auto-detected if not set)

---

## Installing HashLink

If you don't have HashLink installed via Lime, or if you need a standalone HashLink installation, follow these steps:

### Download HashLink from GitHub

1. **Visit the HashLink Releases Page**
   - Go to: https://github.com/HaxeFoundation/hashlink/releases
   - Find the latest release (e.g., `1.15.0`)

2. **Download the Windows Build**
   - Look for the Windows binary package (e.g., `hashlink-1.15.0-win.zip`)
   - Download and extract to a permanent location
   - **Recommended location**: `C:\HashLink` or `C:\Program Files\HashLink`

3. **Verify the Installation**
   
   After extracting, your HashLink directory should contain:
   ```
   C:\HashLink\
   ├── hl.exe              (HashLink runtime)
   ├── libhl.dll           (HashLink runtime library)
   ├── libhl.lib           (Import library - REQUIRED for building)
   ├── include\
   │   └── hl.h            (C API headers - REQUIRED for building)
   └── *.hdll              (Standard library modules)
   ```

> [!IMPORTANT]
> The Windows releases are platform-specific, so the directory structure is flat (no `Windows64` subdirectory). Make sure the downloaded package includes both `include\hl.h` and `libhl.lib` in the root directory. Some packages may only include the runtime (`hl.exe`) without the development files needed for building native extensions.

### Setting the HASHLINK_PATH Environment Variable

The build script needs to know where HashLink is installed. You can set this via the `HASHLINK_PATH` environment variable.

#### Option 1: Set Temporarily (Current Session Only)

```batch
set HASHLINK_PATH=C:\HashLink
```

This only lasts for the current command prompt session.

#### Option 2: Set Permanently (System-Wide)

**Via Command Line (Requires Administrator)**:
```batch
setx HASHLINK_PATH "C:\HashLink" /M
```

**Via GUI**:
1. Press `Win + X` and select **System**
2. Click **Advanced system settings**
3. Click **Environment Variables**
4. Under **System variables** (or **User variables**), click **New**
5. Set:
   - **Variable name**: `HASHLINK_PATH`
   - **Variable value**: `C:\HashLink` (or your installation path)
6. Click **OK** on all dialogs
7. **Restart any open command prompts** for the change to take effect

#### Option 3: Use Lime's HashLink (Automatic)

If you have Lime installed, the build script will automatically detect HashLink at:
```
C:\HaxeToolkit\haxe\lib\lime\8,2,2\templates\bin\hl
```

No environment variable needed in this case.

### Verifying Your HashLink Installation

To verify HashLink is properly installed and accessible:

```batch
# Check if hl.exe is in PATH or HASHLINK_PATH is set
hl --version

# Verify the required files exist
dir "%HASHLINK_PATH%\include\hl.h"
dir "%HASHLINK_PATH%\libhl.lib"
```

If these commands succeed, you're ready to build `civetweb.hdll`.

### Troubleshooting HashLink Installation

#### Downloaded package doesn't include `include` or `Windows64` directories

**Solution**: You may have downloaded a runtime-only package. Look for a package labeled "SDK" or "dev" in the releases, or download the source and build HashLink yourself.

#### HASHLINK_PATH is set but build script can't find files

**Solutions**:
1. Verify the path doesn't have trailing backslashes: `C:\HashLink` (not `C:\HashLink\`)
2. Check for typos in the path
3. Ensure you restarted your command prompt after setting the environment variable
4. Use the full path without spaces, or use quotes if the path contains spaces

#### Using a different HashLink version

The build process should work with HashLink 1.11+ (tested with 1.15.0). If you encounter issues with a specific version:
1. Try the latest stable release
2. Ensure the version matches what Lime uses (if you're using Lime)
3. Check the HashLink release notes for any breaking changes

---

## Build Process

### Quick Start

```batch
cd c:\Src\ge\SideWinder\native\civetweb\hl
build_hdll.bat
```

The script will:
1. ✅ Locate HashLink installation
2. ✅ Configure Visual Studio build environment
3. ✅ Clean previous build artifacts
4. ✅ Compile `civetweb.c` (CivetWeb library)
5. ✅ Compile `civetweb_hl.c` (HashLink bindings)
6. ✅ Link into `civetweb.hdll`

### Build Steps Explained

#### Step 1: Find HashLink Installation

The script searches for HashLink in this order:
1. `HASHLINK_PATH` environment variable (if set)
2. Lime's HashLink: `C:\HaxeToolkit\haxe\lib\lime\8,2,2\templates\bin\hl`
3. `hl.exe` in system PATH

**Verification**:
- Checks for `%HASHLINK_PATH%\include\hl.h`
- Checks for `%HASHLINK_PATH%\libhl.lib` (or `%HASHLINK_PATH%\Windows64\libhl.lib` for Lime's HashLink)

#### Step 2: Setup Visual Studio Environment

Uses `vswhere.exe` to locate the latest Visual Studio installation, then calls `vcvars64.bat` to configure the 64-bit build environment.

**Configured Tools**:
- `cl.exe` - MSVC compiler
- `link.exe` - MSVC linker

#### Step 3: Clean Previous Build Artifacts

Removes old build files:
- `civetweb.obj`
- `civetweb_hl.obj`
- `civetweb.hdll`
- `civetweb.lib`
- `civetweb.exp`

#### Step 4: Compile civetweb.c

Compiles the CivetWeb library source code:

```batch
cl /c /O2 /MD /nologo ^
    /DNO_SSL ^
    /DUSE_WEBSOCKET ^
    ..\civetweb.c ^
    /Fo:civetweb.obj
```

**Compiler Flags**:
- `/c` - Compile only (no linking)
- `/O2` - Optimize for speed
- `/MD` - Link with multithreaded DLL runtime
- `/nologo` - Suppress compiler banner
- `/DNO_SSL` - Disable SSL/TLS support (simplifies dependencies)
- `/DUSE_WEBSOCKET` - Enable WebSocket support
- `/Fo:civetweb.obj` - Output object file name

**Input**: `../civetweb.c` (main CivetWeb implementation)

**Output**: `civetweb.obj`

#### Step 5: Compile civetweb_hl.c

Compiles the HashLink bindings:

```batch
cl /c /O2 /MD /nologo ^
    /I"%HASHLINK_PATH%\include" ^
    /I.. ^
    /DNO_SSL ^
    /DUSE_WEBSOCKET ^
    civetweb_hl.c ^
    /Fo:civetweb_hl.obj
```

**Additional Flags**:
- `/I"%HASHLINK_PATH%\include"` - Include HashLink headers
- `/I..` - Include parent directory (for `civetweb.h`)

**Input**: `civetweb_hl.c` (HashLink bindings implementation)

**Output**: `civetweb_hl.obj`

#### Step 6: Link into civetweb.hdll

Links the object files and libraries into the final `.hdll`:

```batch
link /DLL /NOLOGO ^
    /OUT:civetweb.hdll ^
    civetweb_hl.obj civetweb.obj ^
    libhl.lib ws2_32.lib
```

**Linker Flags**:
- `/DLL` - Create a dynamic link library
- `/NOLOGO` - Suppress linker banner
- `/OUT:civetweb.hdll` - Output file name

**Inputs**:
- `civetweb_hl.obj` - HashLink bindings
- `civetweb.obj` - CivetWeb library
- `libhl.lib` - HashLink import library (copied locally to avoid path issues)
- `ws2_32.lib` - Windows Sockets library (required by CivetWeb)

**Output**: `civetweb.hdll`

---

## Source Files

### Core Files

#### [civetweb.c](file:///c:/Src/ge/SideWinder/native/civetweb/civetweb.c)
- **Size**: ~659 KB
- **Description**: Complete CivetWeb embedded web server implementation
- **Features**: HTTP server, WebSocket support, request handling
- **Configuration**: Compiled with `NO_SSL` and `USE_WEBSOCKET` flags

#### [civetweb.h](file:///c:/Src/ge/SideWinder/native/civetweb/civetweb.h)
- **Size**: ~70 KB
- **Description**: CivetWeb C API header file
- **Defines**: Server configuration, callback types, API functions

#### [civetweb_hl.c](file:///c:/Src/ge/SideWinder/native/civetweb/hl/civetweb_hl.c)
- **Size**: ~11 KB
- **Description**: HashLink bindings for CivetWeb
- **Exports**: Server management, HTTP request/response handling, WebSocket support

### Supporting Files

The following `.inl` files are included by `civetweb.c`:
- `handle_form.inl` - Form data handling
- `match.inl` - Pattern matching utilities
- `md5.inl` - MD5 hashing
- `response.inl` - HTTP response utilities
- `sha1.inl` - SHA-1 hashing
- `timer.inl` - Timer utilities
- `sort.inl` - Sorting utilities

---

## HashLink API Exported

The `civetweb.hdll` library exports these functions to HashLink:

### Server Management
- `create(host, port, documentRoot)` → `hl_civetweb_server*`
- `start(server, handler)` → `bool`
- `stop(server)` → `void`
- `is_running(server)` → `bool`
- `get_port(server)` → `int`
- `get_host(server)` → `bytes`
- `free(server)` → `void`

### WebSocket Support
- `set_websocket_connect_handler(handler)` → `void`
- `set_websocket_ready_handler(handler)` → `void`
- `set_websocket_data_handler(handler)` → `void`
- `set_websocket_close_handler(handler)` → `void`
- `websocket_send(conn, opcode, data, data_len)` → `int`
- `websocket_close(conn, code, reason)` → `void`

---

## Integration with SideWinder

### Deployment

After building, the `.hdll` must be copied to the HashLink runtime directory:

**Option 1: Manual Copy**
```batch
copy civetweb.hdll c:\Src\ge\SideWinder\Export\hl\bin\
```

**Option 2: Interactive Prompt**
The build script offers to copy to the HashLink directory automatically.

### Usage in Haxe

The library is accessed via the `CivetWebAdapter` class:

```haxe
import sidewinder.CivetWebAdapter;

var adapter = new CivetWebAdapter();
adapter.start("127.0.0.1", 8080, "./public");
```

See [CivetWebAdapter.hx](file:///c:/Src/ge/SideWinder/Source/sidewinder/CivetWebAdapter.hx) for implementation details.

---

## Troubleshooting

### Build Errors

#### Error: Cannot find HashLink installation

**Symptoms**:
```
ERROR: Cannot find HashLink installation
```

**Solutions**:
1. Set `HASHLINK_PATH` environment variable:
   ```batch
   set HASHLINK_PATH=C:\HaxeToolkit\haxe\lib\lime\8,2,2\templates\bin\hl
   ```
2. Ensure Lime is installed: `haxelib install lime`
3. Verify `hl.exe` is in PATH

#### Error: Cannot find vswhere.exe

**Symptoms**:
```
ERROR: Cannot find vswhere.exe
```

**Solutions**:
1. Install Visual Studio 2017 or later
2. Ensure C++ development tools are installed
3. Verify installation at: `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe`

#### Error: Cannot find hl.h

**Symptoms**:
```
ERROR: Cannot find hl.h in %HASHLINK_PATH%\include\
```

**Solutions**:
1. Verify `HASHLINK_PATH` points to correct directory
2. Check that `include\hl.h` exists in HashLink installation
3. Reinstall Lime if using Lime's HashLink

#### Error: Cannot find libhl.lib

**Symptoms**:
```
ERROR: Cannot find libhl.lib
```

**Solutions**:
1. Verify HashLink installation is complete
2. For **standalone HashLink** (downloaded from GitHub): Check for `libhl.lib` in the root directory (`C:\HashLink\libhl.lib`)
3. For **Lime's HashLink**: Check for `Windows64\libhl.lib` subdirectory
4. Ensure you're using a Windows 64-bit HashLink build with development files (not just the runtime)

#### Compilation Errors

**Symptoms**:
```
civetweb.c(123): error C2065: 'identifier' undeclared
```

**Solutions**:
1. Ensure all `.inl` files are present in the parent directory
2. Verify `civetweb.h` is accessible
3. Check that `NO_SSL` and `USE_WEBSOCKET` flags are defined

#### Linker Errors

**Symptoms**:
```
LINK : fatal error LNK1181: cannot open input file 'libhl.lib'
```

**Solutions**:
1. The script copies `libhl.lib` locally - ensure this succeeds
2. Check disk space and permissions
3. Verify `libhl.lib` exists:
   - Standalone HashLink: `%HASHLINK_PATH%\libhl.lib`
   - Lime's HashLink: `%HASHLINK_PATH%\Windows64\libhl.lib`

### Runtime Errors

#### Error: civetweb.hdll not found

**Symptoms**:
```
Error: Failed to load library civetweb.hdll
```

**Solutions**:
1. Copy `civetweb.hdll` to `Export\hl\bin\`
2. Ensure the `.hdll` is in the same directory as your `.hl` executable
3. Check that the file is not corrupted (rebuild if necessary)

#### Error: Signature mismatch

**Symptoms**:
```
Error: Invalid signature for civetweb.create
```

**Solutions**:
1. Rebuild `civetweb.hdll` to ensure it matches the current Haxe bindings
2. Verify the `DEFINE_PRIM` declarations in `civetweb_hl.c` match the Haxe extern definitions
3. Clean and rebuild the entire project: `lime clean hl && lime build hl`

---

## Build Configuration

### Compiler Flags Reference

| Flag | Purpose |
|------|---------|
| `/c` | Compile only, don't link |
| `/O2` | Optimize for maximum speed |
| `/MD` | Link with multithreaded DLL runtime (MSVCRT.dll) |
| `/nologo` | Suppress compiler/linker version banner |
| `/I<path>` | Add include directory |
| `/D<macro>` | Define preprocessor macro |
| `/Fo:<file>` | Specify output object file name |

### Preprocessor Definitions

| Macro | Effect |
|-------|--------|
| `NO_SSL` | Disables SSL/TLS support (avoids OpenSSL dependency) |
| `USE_WEBSOCKET` | Enables WebSocket protocol support |

### Why NO_SSL?

SSL/TLS support is disabled to simplify the build process:
- **No OpenSSL dependency** - Avoids needing to build or link OpenSSL libraries
- **Simpler deployment** - No additional DLLs required
- **Development focus** - SSL can be handled by a reverse proxy (nginx, Apache) in production

> [!TIP]
> For production deployments, consider using a reverse proxy with SSL termination rather than enabling SSL in CivetWeb directly.

---

## Advanced Topics

### Enabling SSL Support

To enable SSL/TLS support:

1. **Remove the `/DNO_SSL` flag** from both compilation steps
2. **Add OpenSSL libraries** to the linker step:
   ```batch
   link /DLL /NOLOGO ^
       /OUT:civetweb.hdll ^
       civetweb_hl.obj civetweb.obj ^
       libhl.lib ws2_32.lib ^
       libssl.lib libcrypto.lib
   ```
3. **Include OpenSSL headers** in the compilation:
   ```batch
   /I"C:\OpenSSL\include"
   ```
4. **Add OpenSSL library path**:
   ```batch
   /LIBPATH:"C:\OpenSSL\lib"
   ```

> [!WARNING]
> Enabling SSL requires building or obtaining OpenSSL libraries for Windows, which significantly complicates the build process.

### Custom CivetWeb Configuration

The server is configured in `civetweb_hl.c` with these options:
- `listening_ports` - Port number (from Haxe)
- `document_root` - Static file directory (from Haxe)
- `num_threads` - Worker threads (hardcoded to 4)

To add more options, modify the `options` array in the `start` function.

### Debugging the Build

To see detailed compiler/linker output, remove the `/nologo` flags and the `>nul 2>&1` redirections in the build script.

---

## Related Files

- [CIVETWEB_BUILD_GUIDE_LINUX.md](file:///c:/Src/ge/SideWinder/CIVETWEB_BUILD_GUIDE_LINUX.md) - Linux build guide
- [build_hdll.bat](file:///c:/Src/ge/SideWinder/native/civetweb/hl/build_hdll.bat) - Windows build script
- [build_hdll.sh](file:///c:/Src/ge/SideWinder/native/civetweb/hl/build_hdll.sh) - Linux build script
- [civetweb_hl.c](file:///c:/Src/ge/SideWinder/native/civetweb/hl/civetweb_hl.c) - HashLink bindings source
- [civetweb.c](file:///c:/Src/ge/SideWinder/native/civetweb/civetweb.c) - CivetWeb library source
- [civetweb.h](file:///c:/Src/ge/SideWinder/native/civetweb/civetweb.h) - CivetWeb API header
- [README.md](file:///c:/Src/ge/SideWinder/native/civetweb/README.md) - General CivetWeb bindings documentation
- [CivetWebAdapter.hx](file:///c:/Src/ge/SideWinder/Source/sidewinder/CivetWebAdapter.hx) - Haxe wrapper class

---

## Comparison with MidiSynthHx

The build process is modeled after [MidiSynthHx's build_hdll.bat](file:///c:/Src/ge/MidiSynthHx/MidiSynth/hl/build_hdll.bat), with these differences:

| Aspect | MidiSynthHx | SideWinder CivetWeb |
|--------|-------------|---------------------|
| **Output** | `tsfhl.hdll` | `civetweb.hdll` |
| **Source files** | `tsf_bridge.cpp`, `tsf_hl.c` | `civetweb.c`, `civetweb_hl.c` |
| **Language** | C++ bridge + C bindings | Pure C |
| **Library path** | Uses `/LIBPATH` | Copies `libhl.lib` locally |
| **Dependencies** | TinySoundFont (header-only) | CivetWeb + WinSock2 |
| **Complexity** | Simpler (audio library) | More complex (web server) |

Both follow the same general pattern:
1. Locate HashLink
2. Setup MSVC environment
3. Compile source files
4. Link with `libhl.lib`
5. Produce `.hdll` output

---

## Build Artifacts

After a successful build, the `hl` directory contains:

| File | Size | Description |
|------|------|-------------|
| `civetweb.hdll` | ~163 KB | Final HashLink library (main output) |
| `civetweb.obj` | ~570 KB | CivetWeb compiled object file |
| `civetweb_hl.obj` | ~24 KB | HashLink bindings compiled object file |
| `civetweb.lib` | ~8 KB | Import library (generated by linker) |
| `civetweb.exp` | ~4 KB | Export file (generated by linker) |
| `libhl.lib` | ~134 KB | Copy of HashLink import library |

> [!NOTE]
> Only `civetweb.hdll` is needed for runtime. The other files are build artifacts that can be deleted (they'll be regenerated on next build).

---

## Summary

Building `civetweb.hdll` is a straightforward process once the prerequisites are in place:

1. ✅ Install Visual Studio (C++ tools)
2. ✅ Install HashLink (via Lime)
3. ✅ Run `build_hdll.bat`
4. ✅ Copy `civetweb.hdll` to `Export\hl\bin\`
5. ✅ Build and run SideWinder: `lime test hl`

The build script handles all the complexity of locating tools, configuring the environment, and compiling/linking the native library.
