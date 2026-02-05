#!/bin/bash
# Copy civetweb.hdll to Export/hl/bin after HL build

# Change to the directory where this script is located (project root)
cd "$(dirname "$0")"

SRC="native/civetweb/hl/civetweb.hdll"
PREBUILT="native/civetweb/prebuilt/linux/civetweb.hdll"
DEST="Export/hl/bin/civetweb.hdll"

# If destination already exists, we're done
if [ -f "$DEST" ]; then
    exit 0
fi

# Ensure destination directory exists
mkdir -p "$(dirname "$DEST")"

# Try to copy from build directory first, then prebuilt
if [ -f "$SRC" ]; then
    cp -f "$SRC" "$DEST" 2>/dev/null
    exit 0
fi

if [ -f "$PREBUILT" ]; then
    cp -f "$PREBUILT" "$DEST" 2>/dev/null
    exit 0
fi

# If we get here, neither source exists - but don't fail the build
# The file might have been copied by Lime already
if [ -f "$DEST" ]; then
    exit 0
fi

echo "[copy-hl-hdll.sh] WARNING: civetweb.hdll not found in build or prebuilt directories"
echo "[copy-hl-hdll.sh] Please build it by running: native/civetweb/hl/build_hdll.sh"
# Exit with success anyway to not break the build
exit 0
