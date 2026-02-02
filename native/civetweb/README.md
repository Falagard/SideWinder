# CivetWeb HashLink Native Bindings

This directory contains the native C bindings for CivetWeb to work with HashLink.

## Building

### Prerequisites

- GCC or Clang compiler
- HashLink development headers
- Make
- curl (for downloading CivetWeb source)

### Linux/macOS

```bash
# From project root
./build_civetweb.sh

# Or manually
cd native/civetweb
make
make install
```

### Windows

```bash
cd native/civetweb
make
```

The build will:
1. Download CivetWeb source files (civetweb.c and civetweb.h)
2. Compile the C bindings (civetweb_hl.c)
3. Link everything into civetweb.hdll
4. Install to Export/hl/bin/

## Files

- **civetweb_hl.c** - HashLink native bindings implementation
- **Makefile** - Build configuration
- **README.md** - This file

## HashLink API

The native library provides these functions:

- `create(host, port, documentRoot)` - Create server instance
- `start(server, handler)` - Start server with callback
- `stop(server)` - Stop server
- `is_running(server)` - Check if running
- `get_port(server)` - Get port number
- `get_host(server)` - Get host address
- `free(server)` - Free resources

## Usage from Haxe

```haxe
import sidewinder.native.CivetWebNative;

var server = CivetWebNative.create(
    @:privateAccess "127.0.0.1".toUtf8(),
    8000,
    @:privateAccess "./static".toUtf8()
);

var handler = function(req:Dynamic) {
    return {
        statusCode: 200,
        contentType: "text/html",
        body: "<h1>Hello!</h1>",
        bodyLength: 16
    };
};

CivetWebNative.start(server, handler);
```

## Troubleshooting

### Build Errors

**Problem:** `hl.h not found`
- Install HashLink development headers
- Update `HL_INCLUDE` path in Makefile

**Problem:** `curl: command not found`
- Install curl: `apt install curl` or `brew install curl`
- Or manually download civetweb.c and civetweb.h from GitHub

**Problem:** Linker errors
- Check that pthread is available: `apt install build-essential`
- On macOS, ensure Xcode command line tools are installed

### Runtime Errors

**Problem:** `civetweb.hdll not found`
- Run `make install` to copy to Export/hl/bin/
- Or manually copy civetweb.hdll to the directory where your .hl file is

**Problem:** Segmentation fault
- Check that callbacks are properly retained
- Verify all pointers are valid before native calls

## Platform Support

- ✅ Linux (tested)
- ✅ macOS (tested)
- ⚠️ Windows (experimental, may need adjustments)

## CivetWeb Version

The build automatically downloads the latest CivetWeb from the master branch. To use a specific version, modify the Makefile URLs.

## License

CivetWeb is licensed under the MIT License.
These bindings are part of the SideWinder project.
