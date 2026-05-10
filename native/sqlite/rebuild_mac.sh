#!/bin/bash
set -e

echo "========================================"
echo "Building sqlite.hdll for HashLink (macOS)"
echo "========================================"

# Compile with Advanced Flags
FLAGS="-DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_SESSION -DSQLITE_ENABLE_PREUPDATE_HOOK -DSQLITE_USE_ALLOCA -DSQLITE_THREADSAFE=1"

# Paths from Lime's bundled HashLink
HL_INCLUDE="/usr/local/lib/haxe/lib/lime/8,3,1/templates/bin/hl/include"
HL_LIB="/usr/local/lib/haxe/lib/lime/8,3,1/templates/bin/hl/Mac64"

echo "Compiling with: $FLAGS"

gcc -O2 -dynamiclib -arch x86_64 \
    -I"$HL_INCLUDE" -I. \
    $FLAGS \
    sqlite.c sqlite3.c \
    -L"$HL_LIB" -lhl -lpthread -lm -ldl \
    -o sqlite.hdll

if [ $? -eq 0 ]; then
    echo "Build Success: sqlite.hdll"
    echo ""
    echo "Copying to SideWinder prebuilt locations..."
    mkdir -p ../civetweb/prebuilt/mac
    cp sqlite.hdll ../civetweb/prebuilt/mac/sqlite.hdll
    echo "Copied to ../civetweb/prebuilt/mac/sqlite.hdll"
else
    echo "Build Failed!"
    exit 1
fi
