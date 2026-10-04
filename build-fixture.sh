#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
fixture_mode=chat
if (( $# > 0 )); then
  [[ $# == 1 && "$1" == --code ]] || { print -u2 'Usage: ./build-fixture.sh [--code]'; exit 2; }
  fixture_mode=code
fi
./sign-app.sh --check
mkdir -p .build/cache dist
staging=$(mktemp -d "$PWD/.build/fixture-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/A畜伴侣测试输入框.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/AppMenus.swift Tests/ChatFixture.swift -o "$app/Contents/MacOS/Fixture"
cp Tests/fixture.html "$app/Contents/Resources/fixture.html"
cp Tests/code-fixture.html "$app/Contents/Resources/code-fixture.html"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.achu.fixture</string><key>CFBundleName</key><string>A畜伴侣测试输入框</string><key>CFBundleExecutable</key><string>Fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :ACHUFixtureMode string $fixture_mode" "$app/Contents/Info.plist"
./sign-app.sh "$app"
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
rm -rf "dist/A畜伴侣测试输入框.app"
mv "$app" "dist/A畜伴侣测试输入框.app"
