#!/bin/bash
# Copy civetweb.hdll and sqlite.hdll to Export/hl/bin after HL build

# Change to the directory where this script is located (project root)
cd "$(dirname "$0")"

SRC="native/civetweb/hl/civetweb.hdll"
PREBUILT="native/civetweb/prebuilt/linux/civetweb.hdll"
DEST="Export/hl/bin/civetweb.hdll"

# Ensure destination directory exists
mkdir -p "$(dirname "$DEST")"

# Copy civetweb.hdll
# If destination already exists, we're done with civetweb
if [ ! -f "$DEST" ]; then
    # Try to copy from build directory first, then prebuilt
    if [ -f "$SRC" ]; then
        cp -f "$SRC" "$DEST" 2>/dev/null
    elif [ -f "$PREBUILT" ]; then
        cp -f "$PREBUILT" "$DEST" 2>/dev/null
    else
        # If we get here, neither source exists - but don't fail the build
        # The file might have been copied by Lime already
        if [ ! -f "$DEST" ]; then
            echo "[copy-hl-hdll.sh] WARNING: civetweb.hdll not found in build or prebuilt directories"
            echo "[copy-hl-hdll.sh] Please build it by running: native/civetweb/hl/build_hdll.sh"
        fi
    fi
fi

# Copy sqlite.hdll from HashLink installation
SQLITE_DEST="Export/hl/bin/sqlite.hdll"
if [ ! -f "$SQLITE_DEST" ]; then
    # Use HASHLINK_PATH environment variable if set, otherwise try default locations
    if [ -n "$HASHLINK_PATH" ]; then
        SQLITE_SRC="$HASHLINK_PATH/sqlite.hdll"
    elif [ -f "/usr/local/lib/sqlite.hdll" ]; then
        SQLITE_SRC="/usr/local/lib/sqlite.hdll"
    elif [ -f "/usr/lib/sqlite.hdll" ]; then
        SQLITE_SRC="/usr/lib/sqlite.hdll"
    else
        SQLITE_SRC="$HOME/.local/lib/sqlite.hdll"
    fi
    
    if [ -f "$SQLITE_SRC" ]; then
        cp -f "$SQLITE_SRC" "$SQLITE_DEST" 2>/dev/null
        echo "[copy-hl-hdll.sh] Copied sqlite.hdll from $SQLITE_SRC"
    else
        echo "[copy-hl-hdll.sh] WARNING: sqlite.hdll not found at $SQLITE_SRC"
        echo "[copy-hl-hdll.sh] Set HASHLINK_PATH environment variable to your HashLink installation path"
    fi
fi

# Exit with success to not break the build
exit 0
