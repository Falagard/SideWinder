#!/bin/bash
set -e

echo "========================================"
echo "Building civetweb.hdll for HashLink (macOS)"
echo "========================================"

# Paths from Lime's bundled HashLink
HL_INCLUDE="/usr/local/lib/haxe/lib/lime/8,3,1/templates/bin/hl/include"
HL_LIB="/usr/local/lib/haxe/lib/lime/8,3,1/templates/bin/hl/Mac64"

# 1. Compile civetweb.c
echo "[1/3] Compiling civetweb.c..."
gcc -c -O2 -arch x86_64 -std=c99 \
    -DNO_SSL \
    -DUSE_WEBSOCKET \
    ../civetweb.c \
    -o civetweb.o

# 2. Compile civetweb_hl.c
echo "[2/3] Compiling civetweb_hl.c..."
gcc -c -O2 -arch x86_64 -std=c99 \
    -I"$HL_INCLUDE" \
    -I.. \
    -DNO_SSL \
    -DUSE_WEBSOCKET \
    civetweb_hl.c \
    -o civetweb_hl.o

# 3. Link into civetweb.hdll
echo "[3/3] Linking civetweb.hdll..."
gcc -dynamiclib -arch x86_64 -o civetweb.hdll \
    civetweb_hl.o civetweb.o \
    -L"$HL_LIB" -lhl \
    -lpthread

if [ $? -eq 0 ]; then
    echo "Build Success: civetweb.hdll"
    echo ""
    echo "Copying to SideWinder prebuilt locations..."
    mkdir -p ../prebuilt/mac
    cp civetweb.hdll ../prebuilt/mac/civetweb.hdll
    echo "Copied to ../prebuilt/mac/civetweb.hdll"
else
    echo "Build Failed!"
    exit 1
fi
