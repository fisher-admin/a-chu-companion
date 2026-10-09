#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
sources=(Sources/*.swift)
sources=("${(@)sources:#Sources/Main.swift}")
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" "${sources[@]}" Tests/LanguageSmokeTests.swift -o .build/language-smoke-tests
.build/language-smoke-tests "$@"
