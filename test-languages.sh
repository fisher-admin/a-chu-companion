#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/GeminiTranslation.swift Sources/TextTranslation.swift Sources/TranslationStructure.swift Sources/MarkdownTable.swift Tests/LanguageSmokeTests.swift -o .build/language-smoke-tests
.build/language-smoke-tests "$@"
