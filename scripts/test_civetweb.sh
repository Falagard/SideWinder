#!/bin/bash
# Quick test script for CivetWeb HashLink adapter

echo "================================"
echo "CivetWeb HashLink Adapter Test"
echo "================================"
echo ""

# Check if civetweb.hdll exists
if [ ! -f "Export/hl/bin/civetweb.hdll" ]; then
    echo "❌ civetweb.hdll not found!"
    echo ""
    echo "Building now..."
    ./build_civetweb.sh
    
    if [ $? -ne 0 ]; then
        echo "❌ Build failed!"
        exit 1
    fi
fi

echo "✅ civetweb.hdll found"
echo ""

# Check if we should update Main.hx
echo "📝 Checking Main.hx configuration..."
if grep -q "WebServerType.SnakeServer" Source/Main.hx; then
    echo "⚠️  Main.hx is configured for SnakeServer"
    echo ""
    echo "To test CivetWeb, update Source/Main.hx:"
    echo "  Change: WebServerType.SnakeServer"
    echo "  To:     WebServerType.CivetWeb"
    echo ""
    read -p "Would you like to make this change now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sed -i 's/WebServerType\.SnakeServer/WebServerType.CivetWeb/g' Source/Main.hx
        echo "✅ Updated Main.hx to use CivetWeb"
    else
        echo "⏭️  Skipping update. Testing will use current configuration."
    fi
fi

echo ""
echo "🚀 Starting server..."
echo ""

# Run the server
lime test hl

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
