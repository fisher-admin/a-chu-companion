#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache "dist/A畜伴侣.app/Contents/MacOS" "dist/A畜伴侣.app/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos15.0 -module-cache-path "$PWD/.build/cache" Sources/*.swift -o "dist/A畜伴侣.app/Contents/MacOS/Yiqiao"
cat > "dist/A畜伴侣.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.yiqiao.translator</string>
<key>CFBundleName</key><string>A畜伴侣</string>
<key>CFBundleDisplayName</key><string>A畜伴侣</string>
<key>CFBundleExecutable</key><string>Yiqiao</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAccessibilityUsageDescription</key><string>将翻译后的英文填入你选定的软件输入框，并按你的设置触发发送。</string>
</dict></plist>
PLIST
codesign --force --sign - "dist/A畜伴侣.app"
plutil -lint "dist/A畜伴侣.app/Contents/Info.plist"
printf 'Built: %s/dist/A畜伴侣.app\n' "$PWD"
