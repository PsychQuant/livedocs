#!/bin/bash
# Build MCPB package for Claude Desktop

set -e

cd "$(dirname "$0")/.."

echo "Building release..."
swift build -c release

echo "Copying binary to mcpb/server/..."
cp .build/release/CheLiveDocsMCP mcpb/server/

echo "Packaging mcpb..."
cd mcpb
rm -f che-livedocs-mcp.mcpb
zip -r che-livedocs-mcp.mcpb manifest.json icon.png PRIVACY.md server/

echo "Done! Package: mcpb/che-livedocs-mcp.mcpb"
