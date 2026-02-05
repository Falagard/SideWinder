# Building CivetWeb on Linux

This guide covers building the `civetweb.hdll` HashLink native library on Linux.

## Prerequisites

### Required Software

1. **GCC Compiler**
   ```bash
   sudo apt-get install build-essential  # Debian/Ubuntu
   sudo yum install gcc                  # RHEL/CentOS
   ```

2. **HashLink**
   - Install from package manager or build from source
   - Must include development files (`hl.h`, `libhl.so`)
   
   **Ubuntu/Debian:**
   ```bash
   sudo add-apt-repository ppa:haxe/releases -y
   sudo apt-get update
   sudo apt-get install hashlink libhl-dev
   ```
   
   **Build from source:**
   ```bash
   git clone https://github.com/HaxeFoundation/hashlink.git
   cd hashlink
   make
   sudo make install
   ```

3. **Verify Installation**
   ```bash
   hl --version
   ls /usr/local/include/hl.h
   ls /usr/local/lib/libhl.so
   ```

## Build Process

### Quick Start

```bash
cd native/civetweb/hl
chmod +x build_hdll.sh
./build_hdll.sh
```

The script will:
1. ✅ Locate HashLink installation
2. ✅ Clean previous build artifacts
3. ✅ Compile `civetweb.c` (CivetWeb library)
4. ✅ Compile `civetweb_hl.c` (HashLink bindings)
5. ✅ Link into `civetweb.hdll`

### Build Steps Explained

#### Step 1: Find HashLink Installation

The script searches for HashLink in this order:
1. `HASHLINK_PATH` environment variable (if set)
2. `hl` executable in PATH
3. Common installation paths (`/usr/local`, `/usr`)

**Verification**:
- Checks for `$HASHLINK_PATH/include/hl.h`
- Checks for `libhl.so` in either:
  - `$HASHLINK_PATH/lib/libhl.so`
  - `$HASHLINK_PATH/libhl.so`

#### Step 2: Compile civetweb.c

Compiles the CivetWeb library source code:

```bash
gcc -c -O2 -fPIC -std=c99 \
    -DNO_SSL \
    -DUSE_WEBSOCKET \
    ../civetweb.c \
    -o civetweb.o
```

**Compiler Flags**:
- `-c` - Compile only (no linking)
- `-O2` - Optimize for speed
- `-fPIC` - Position Independent Code (required for shared libraries)
- `-std=c99` - Use C99 standard
- `-DNO_SSL` - Disable SSL/TLS support
- `-DUSE_WEBSOCKET` - Enable WebSocket support

#### Step 3: Compile civetweb_hl.c

Compiles the HashLink bindings:

```bash
gcc -c -O2 -fPIC -std=c99 \
    -I"$HASHLINK_PATH/include" \
    -I.. \
    -DNO_SSL \
    -DUSE_WEBSOCKET \
    civetweb_hl.c \
    -o civetweb_hl.o
```

#### Step 4: Link into civetweb.hdll

Links the object files and libraries:

```bash
gcc -shared -o civetweb.hdll \
    civetweb_hl.o civetweb.o \
    -L"$HL_LIB_PATH" -lhl \
    -lpthread
```

**Linker Flags**:
- `-shared` - Create a shared library
- `-L` - Library search path
- `-lhl` - Link with HashLink library
- `-lpthread` - Link with POSIX threads library

## Integration with SideWinder

### Deployment

After building, the `.hdll` must be copied to the HashLink runtime directory:

**Manual Copy:**
```bash
cp civetweb.hdll ../../../Export/hl/bin/
```

**Using the copy script:**
```bash
cd ../../..  # Back to project root
chmod +x copy-hl-hdll.sh
./copy-hl-hdll.sh
```

**Automatic (via Lime):**
The `project.xml` postbuild event automatically runs `copy-hl-hdll.sh` after building:
```bash
lime build hl
```

### Full Build Workflow

```bash
# 1. Build the native library
cd native/civetweb/hl
./build_hdll.sh

# 2. Return to project root
cd ../../..

# 3. Build and run the project
lime build hl
lime test hl
```

## Troubleshooting

### Error: Cannot find HashLink installation

**Solutions**:
1. Set `HASHLINK_PATH` environment variable:
   ```bash
   export HASHLINK_PATH=/usr/local
   ```
2. Ensure HashLink is installed: `hl --version`
3. Install development files: `sudo apt-get install libhl-dev`

### Error: Cannot find hl.h

**Solutions**:
1. Verify HashLink development files are installed
2. Check that `include/hl.h` exists in HashLink installation
3. Install from source if package doesn't include headers

### Error: Cannot find libhl.so

**Solutions**:
1. Verify HashLink installation is complete
2. Check for `libhl.so` in:
   - `/usr/local/lib/libhl.so`
   - `/usr/lib/libhl.so`
3. Run `sudo ldconfig` to update library cache

### Compilation Errors

**Symptoms**:
```
civetweb.c:123: error: 'identifier' undeclared
```

**Solutions**:
1. Ensure all `.inl` files are present in the parent directory
2. Verify `civetweb.h` is accessible
3. Check that `NO_SSL` and `USE_WEBSOCKET` flags are defined

### Linker Errors

**Symptoms**:
```
/usr/bin/ld: cannot find -lhl
```

**Solutions**:
1. Verify `libhl.so` exists in the library path
2. Add library path manually:
   ```bash
   export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
   ```
3. Run `sudo ldconfig` to update library cache

### Runtime Errors

#### Error: civetweb.hdll not found

**Solutions**:
1. Copy `civetweb.hdll` to `Export/hl/bin/`
2. Ensure the `.hdll` is in the same directory as your `.hl` executable
3. Check file permissions: `chmod 755 civetweb.hdll`

#### Error: libhl.so not found at runtime

**Solutions**:
1. Add HashLink library path to `LD_LIBRARY_PATH`:
   ```bash
   export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
   ```
2. Or add to `/etc/ld.so.conf.d/hashlink.conf`:
   ```bash
   echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/hashlink.conf
   sudo ldconfig
   ```

## Platform Differences

| Aspect | Windows | Linux |
|--------|---------|-------|
| **Build Script** | `build_hdll.bat` | `build_hdll.sh` |
| **Compiler** | MSVC (`cl.exe`) | GCC (`gcc`) |
| **Output** | `civetweb.hdll` | `civetweb.hdll` |
| **Library** | `libhl.lib` + `ws2_32.lib` | `libhl.so` + `pthread` |
| **Copy Script** | `copy-hl-hdll.bat` | `copy-hl-hdll.sh` |

Both platforms produce the same `.hdll` file format that HashLink can load.

## Summary

Building `civetweb.hdll` on Linux:

1. ✅ Install GCC and HashLink development files
2. ✅ Run `./build_hdll.sh` in `native/civetweb/hl/`
3. ✅ Copy `civetweb.hdll` to `Export/hl/bin/` (or use `lime build hl`)
4. ✅ Run SideWinder: `lime test hl`
