#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/Editor.swift Tests/EditorTests.swift -o .build/editor-tests
.build/editor-tests
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/ReplyCore.swift Tests/ReplyTests.swift -o .build/reply-tests
.build/reply-tests
