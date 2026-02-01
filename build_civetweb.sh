#!/bin/bash
# Build script for CivetWeb HashLink native library

set -e

echo "===================================="
echo "Building CivetWeb HashLink Bindings"
echo "===================================="

# Change to native directory
cd "$(dirname "$0")/native/civetweb"

# Build the native library
echo "Building civetweb.hdll..."
make clean
make all
make install

echo ""
echo "===================================="
echo "Build complete!"
echo "===================================="
echo "The civetweb.hdll library has been installed to Export/hl/bin/"
echo ""
echo "To use CivetWeb:"
echo "1. Run: lime test hl"
echo "2. Or manually: cd Export/hl/bin && hl hlboot.dat"
echo ""
