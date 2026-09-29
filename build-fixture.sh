#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache "dist/A畜伴侣测试输入框.app/Contents/MacOS" "dist/A畜伴侣测试输入框.app/Contents/Resources"
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/AppMenus.swift Tests/ChatFixture.swift -o "dist/A畜伴侣测试输入框.app/Contents/MacOS/Fixture"
cp Tests/fixture.html "dist/A畜伴侣测试输入框.app/Contents/Resources/fixture.html"
cat > "dist/A畜伴侣测试输入框.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.yiqiao.fixture</string><key>CFBundleName</key><string>A畜伴侣测试输入框</string><key>CFBundleExecutable</key><string>Fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
codesign --force --sign - "dist/A畜伴侣测试输入框.app"
