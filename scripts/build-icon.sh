#!/bin/zsh
# Package the source artwork as a native macOS icon, preserving its transparency.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
icon_directory="$(mktemp -d "$PWD/build/icon.XXXXXX")"
trap 'rm -rf "$icon_directory"' EXIT
iconset_directory="$icon_directory/AppIcon.iconset"
mkdir -p "$iconset_directory"
for size in 16 32 128 256 512; do
    sips --resampleHeightWidth "$size" "$size" Resources/AppIcon.png --out "$iconset_directory/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips --resampleHeightWidth "$retina_size" "$retina_size" Resources/AppIcon.png --out "$iconset_directory/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset_directory" --output Resources/AppIcon.icns
print "Built Resources/AppIcon.icns"
