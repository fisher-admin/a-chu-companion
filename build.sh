#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
unsigned_build=false
case "${1:-}" in
  "") [[ $# == 0 ]] || { print -u2 'Usage: ./build.sh [--unsigned]'; exit 2; } ;;
  --unsigned) [[ $# == 1 ]] || { print -u2 'Usage: ./build.sh [--unsigned]'; exit 2; }; unsigned_build=true ;;
  *) print -u2 'Usage: ./build.sh [--unsigned]'; exit 2 ;;
esac
if ! $unsigned_build; then ./sign-app.sh --check; fi
mkdir -p .build/cache dist
staging=$(mktemp -d "$PWD/.build/package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/A畜伴侣.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos15.0 -module-cache-path "$PWD/.build/cache" Sources/*.swift -o "$app/Contents/MacOS/AChuCompanion"
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/CompanionIcon.swift Tools/GenerateIcons.swift -o .build/generate-icons
.build/generate-icons "$staging/AChuCompanion.iconset"
cp -R Bridge "$app/Contents/Resources/Bridge"
rm -rf "$app/Contents/Resources/Bridge/__pycache__"
iconutil -c icns -o "$app/Contents/Resources/AChuCompanion.icns" "$staging/AChuCompanion.iconset"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.achu.companion</string>
<key>CFBundleName</key><string>A畜伴侣</string>
<key>CFBundleDisplayName</key><string>A畜伴侣</string>
<key>CFBundleExecutable</key><string>AChuCompanion</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.8</string>
    <key>CFBundleVersion</key><string>75</string>
<key>CFBundleIconFile</key><string>AChuCompanion</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAccessibilityUsageDescription</key><string>将译文填入你选定的软件输入框，并按你的设置触发发送和读取 Claude 回复。</string>
</dict></plist>
PLIST
if ! $unsigned_build; then
  ./sign-app.sh "$app"
  codesign --verify --strict "$app"
fi
plutil -lint "$app/Contents/Info.plist"
destination="dist/A畜伴侣.app"
if $unsigned_build; then
  mkdir -p dist/unsigned
  destination="dist/unsigned/A畜伴侣.app"
fi
rm -rf "$destination"
mv "$app" "$destination"
printf 'Built: %s/%s\n' "$PWD" "$destination"
if $unsigned_build; then
  print 'Verification build only: no local signing identity, no installation, no Apple notarization.'
fi
