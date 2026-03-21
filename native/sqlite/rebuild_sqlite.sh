#!/bin/bash
set -e

echo "========================================"
echo "Building sqlite.hdll for HashLink (Linux)"
echo "========================================"

# Compile with Advanced Flags
# Note: SSL is not needed for SQLite, but we need libhl, pthread, m (math), and dl (dynamic loader).
FLAGS="-DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_SESSION -DSQLITE_ENABLE_PREUPDATE_HOOK -DSQLITE_USE_ALLOCA -DSQLITE_THREADSAFE=1"

echo "Compiling with: $FLAGS"

gcc -O2 -shared -fPIC \
    -I/hl/include -I. \
    $FLAGS \
    sqlite.c sqlite3.c \
    -L/hl/lib -lhl -lpthread -lm -ldl \
    -o sqlite.hdll

if [ $? -eq 0 ]; then
    echo "Build Success: sqlite.hdll"
    echo ""
    echo "Copying to SideWinder prebuilt locations..."
    mkdir -p ../civetweb/prebuilt/linux
    cp sqlite.hdll ../civetweb/prebuilt/linux/sqlite.hdll
    echo "Copied to ../civetweb/prebuilt/linux/sqlite.hdll"
else
    echo "Build Failed!"
    exit 1
fi
