#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build -c "$configuration" "${swift_options[@]}"
binary_directory="$(swift build -c "$configuration" --show-bin-path "${swift_options[@]}")"
app_directory="$PWD/build/PicTuner.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/PicTuner" "$app_directory/Contents/MacOS/PicTuner"
cp Resources/Info.plist "$app_directory/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_directory/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_directory"
print "Built $app_directory"
