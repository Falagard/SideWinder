#!/bin/bash
# Build script for civetweb.hdll (HashLink native library)
# Compiles CivetWeb bridge for HashLink on Linux

set -e

echo "========================================"
echo "Building civetweb.hdll for HashLink"
echo "========================================"
echo ""

# ==============================
# 1. Find HashLink installation
# ==============================
if [ -z "$HASHLINK_PATH" ]; then
    echo "HASHLINK_PATH not set, attempting to locate HashLink..."
    
    # Try to find hl in PATH
    if command -v hl &> /dev/null; then
        HL_BIN=$(which hl)
        HASHLINK_PATH=$(dirname "$HL_BIN")
        echo "Found HashLink at: $HASHLINK_PATH"
    else
        # Try common installation paths
        if [ -d "/usr/local/lib/hl" ]; then
            HASHLINK_PATH="/usr/local"
        elif [ -d "/usr/lib/hl" ]; then
            HASHLINK_PATH="/usr"
        else
            echo "ERROR: Cannot find HashLink installation"
            echo "Please set HASHLINK_PATH environment variable to your HashLink installation directory"
            echo "Example: export HASHLINK_PATH=/usr/local"
            exit 1
        fi
        echo "Found HashLink at: $HASHLINK_PATH"
    fi
else
    echo "Using HASHLINK_PATH: $HASHLINK_PATH"
fi

# Verify HashLink files exist
if [ ! -f "$HASHLINK_PATH/include/hl.h" ]; then
    echo "ERROR: Cannot find hl.h in $HASHLINK_PATH/include/"
    echo "Please verify HASHLINK_PATH is correct"
    exit 1
fi

# Check for libhl.so in both possible locations
HL_LIB_PATH=""
if [ -f "$HASHLINK_PATH/lib/libhl.so" ]; then
    HL_LIB_PATH="$HASHLINK_PATH/lib"
    echo "Found libhl.so in lib directory"
elif [ -f "$HASHLINK_PATH/libhl.so" ]; then
    HL_LIB_PATH="$HASHLINK_PATH"
    echo "Found libhl.so in root directory"
else
    echo "ERROR: Cannot find libhl.so in either:"
    echo "  - $HASHLINK_PATH/lib/libhl.so"
    echo "  - $HASHLINK_PATH/libhl.so"
    echo "Please verify HASHLINK_PATH is correct"
    exit 1
fi

echo "HashLink headers and libraries found OK"
echo ""

# ==============================
# 2. Clean previous build artifacts
# ==============================
rm -f civetweb.o civetweb_hl.o civetweb.hdll

# ==============================
# 3. Compile civetweb.c (CivetWeb library)
# ==============================
echo "[1/3] Compiling civetweb.c..."
gcc -c -O2 -fPIC -std=c99 \
    -DNO_SSL \
    -DUSE_WEBSOCKET \
    ../civetweb.c \
    -o civetweb.o

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compile civetweb.c"
    exit 1
fi
echo "civetweb.o created successfully"
echo ""

# ==============================
# 4. Compile civetweb_hl.c (HashLink bindings)
# ==============================
echo "[2/3] Compiling civetweb_hl.c..."
gcc -c -O2 -fPIC -std=c99 \
    -I"$HASHLINK_PATH/include" \
    -I.. \
    -DNO_SSL \
    -DUSE_WEBSOCKET \
    civetweb_hl.c \
    -o civetweb_hl.o

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compile civetweb_hl.c"
    exit 1
fi
echo "civetweb_hl.o created successfully"
echo ""

# ==============================
# 5. Link into civetweb.hdll
# ==============================
echo "[3/3] Linking civetweb.hdll..."
echo "Using library path: $HL_LIB_PATH"

gcc -shared -o civetweb.hdll \
    civetweb_hl.o civetweb.o \
    -L"$HL_LIB_PATH" -lhl \
    -lpthread

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to link civetweb.hdll"
    exit 1
fi

echo ""
echo "========================================"
echo "Build completed successfully!"
echo "========================================"
echo "Output: civetweb.hdll"
echo ""
echo "Next steps:"
echo "1. Copy civetweb.hdll to Export/hl/bin/ (or use copy-hl-hdll.sh)"
echo "2. Run: lime build hl"
echo "3. Run: lime test hl"
echo ""
