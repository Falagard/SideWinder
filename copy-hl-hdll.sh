#!/bin/bash
# Copy civetweb.hdll to Export/hl/bin after HL build

SRC="native/civetweb/hl/civetweb.hdll"
DEST="Export/hl/bin/civetweb.hdll"

if [ -f "$SRC" ]; then
    mkdir -p "$(dirname "$DEST")"
    cp -f "$SRC" "$DEST"
    echo "Copied $SRC to $DEST"
else
    echo "ERROR: $SRC not found!"
    exit 1
fi
