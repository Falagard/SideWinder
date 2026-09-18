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

# -install_name must match the actual output filename (sqlite.hdll), matching the
# convention every other custom hdll in this repo already follows (vlc.hdll, hodbc.hdll).
# Without this, gcc/ld embeds some other name (observed: "sqlite-mac.hdll", from an
# earlier build of this same script under a different output name) as this dylib's
# Mach-O ID. The `hl` bytecode interpreter never notices since it dlopens hdlls by
# literal filename, ignoring the embedded ID -- but a native-compiled `hlc` executable's
# real dyld link DOES resolve dependents by embedded ID, and lime's own postbuild
# "rewrite every embedded ID to @executable_path/<filename>" step assumes embedded ID
# equals filename, so a mismatch here silently breaks hlc builds specifically. See
# docs/sessions/20260918-LimeForkForHlcFixes.md / HlcExploratoryHandoff.md.
gcc -O2 -dynamiclib -arch x86_64 \
    -install_name sqlite.hdll \
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
