#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/Editor.swift Sources/MessageText.swift Tests/EditorTests.swift -o .build/editor-tests
.build/editor-tests
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/ReplyCore.swift Tests/ReplyTests.swift -o .build/reply-tests
.build/reply-tests
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/AccessibilityPermissionMonitor.swift Sources/Core.swift Sources/ReplyCore.swift Sources/ClaudeAccessibility.swift Sources/TargetBridge.swift Sources/Credentials.swift Sources/ReplyMonitor.swift Sources/TranslatorModel.swift Sources/TextTranslation.swift Tests/PermissionTests.swift -o .build/permission-tests
.build/permission-tests

swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/TextTranslation.swift Tests/TranslationPipelineTests.swift -o .build/translation-pipeline-tests
.build/translation-pipeline-tests

swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/AccessibilityPermissionMonitor.swift Sources/Core.swift Sources/ReplyCore.swift Sources/ClaudeAccessibility.swift Sources/TargetBridge.swift Sources/Credentials.swift Sources/ReplyMonitor.swift Sources/TranslatorModel.swift Sources/TextTranslation.swift Tests/ModelTests.swift -o .build/model-tests
.build/model-tests

swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/ClaudeUsageCore.swift Tests/UsageTests.swift -o .build/usage-tests
.build/usage-tests
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/ClaudeUsageCore.swift Sources/ClaudeDesktopSession.swift Sources/ClaudeUsageMonitor.swift Tests/UsageMonitorTests.swift -o .build/usage-monitor-tests
.build/usage-monitor-tests
