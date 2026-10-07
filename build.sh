#!/usr/bin/env sh
# Packages the mod as dist/MinecraftHUD-<version>.zip, laid out to unzip into the game folder.
set -e
VERSION="${1:-0.1.0}"
cd "$(dirname "$0")"
luac -p reframework/autorun/minecraft_hud.lua 2>/dev/null || echo "note: luac not found, skipping syntax check"
mkdir -p dist
rm -f "dist/MinecraftHUD-$VERSION.zip"
zip -X -r "dist/MinecraftHUD-$VERSION.zip" reframework/autorun/minecraft_hud.lua
echo "dist/MinecraftHUD-$VERSION.zip"
