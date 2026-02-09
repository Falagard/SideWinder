#!/bin/bash

echo "========================================"
echo "Publishing CivetWeb Prebuilt Library"
echo "========================================"
echo

# Change to the directory where this script is located
cd "$(dirname "$0")"

SRC="hl/civetweb.hdll"
DEST="prebuilt/linux/civetweb.hdll"

# Check if source exists
if [ ! -f "$SRC" ]; then
    echo "ERROR: Local build not found at $SRC"
    echo
    echo "Please build the library first by running:"
    echo "  ./rebuild_civetweb.sh"
    echo
    exit 1
fi

# Ensure destination directory exists
mkdir -p "prebuilt/linux"

# Show file information
echo "Source: $SRC"
if [ -f "$SRC" ]; then
    SIZE=$(stat -c%s "$SRC" 2>/dev/null || stat -f%z "$SRC" 2>/dev/null)
    MODIFIED=$(stat -c%y "$SRC" 2>/dev/null || stat -f%Sm "$SRC" 2>/dev/null)
    echo "  Size: $SIZE bytes"
    echo "  Modified: $MODIFIED"
fi
echo

echo "Destination: $DEST"
if [ -f "$DEST" ]; then
    SIZE=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null)
    MODIFIED=$(stat -c%y "$DEST" 2>/dev/null || stat -f%Sm "$DEST" 2>/dev/null)
    echo "  Current Size: $SIZE bytes"
    echo "  Current Modified: $MODIFIED"
else
    echo "  (File does not exist yet)"
fi
echo

# Confirm before overwriting
read -p "Update prebuilt library? This will be tracked in git. (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "Cancelled."
    exit 0
fi

# Copy the file
cp "$SRC" "$DEST"
if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Failed to copy file!"
    exit 1
fi

echo
echo "========================================"
echo "Success!"
echo "========================================"
echo
echo "Updated: $DEST"
if [ -f "$DEST" ]; then
    SIZE=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null)
    MODIFIED=$(stat -c%y "$DEST" 2>/dev/null || stat -f%Sm "$DEST" 2>/dev/null)
    echo "  Size: $SIZE bytes"
    echo "  Modified: $MODIFIED"
fi
echo
echo "NEXT STEPS:"
echo "1. Test the prebuilt library: lime build hl"
echo "2. Commit the change: git add $DEST"
echo "3. Include in your commit message that civetweb.hdll was updated"
echo
