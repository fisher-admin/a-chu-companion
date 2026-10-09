#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
sources=(Sources/*.swift)
sources=("${(@)sources:#Sources/Main.swift}")
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" "${sources[@]}" Tests/BridgeSocketTests.swift -o .build/bridge-socket-tests
.build/bridge-socket-tests
python3 -m unittest discover -s Tests -p BridgeTests.py
python3 -m unittest discover -s Tests -p ActiveUsageTests.py
python3 -m unittest discover -s Tests -p CLIDeliveryOriginTests.py
node --test Tests/BridgeChromeTests.cjs Tests/BridgeWorkerTests.cjs Tests/WebUsageTests.cjs
