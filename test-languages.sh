#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/TextTranslation.swift Tests/LanguageSmokeTests.swift -o .build/language-smoke-tests
.build/language-smoke-tests "$@"
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/TextTranslation.swift Sources/TranslationGuard.swift Sources/AICircuit.swift Sources/FailoverTranslator.swift Sources/SystemTranslator.swift Sources/StreamSegmenter.swift Sources/StreamTranslationPipeline.swift Tests/StreamSystemSmokeTests.swift -o .build/stream-system-smoke-tests
.build/stream-system-smoke-tests
