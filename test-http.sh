#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
port_file=$(mktemp /private/tmp/yiqiao-port.XXXXXX)
python3 Tests/MockServer.py "$port_file" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
for attempt in {1..30}; do
  [[ -s "$port_file" ]] && break
  sleep 0.1
done
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Tests/HTTPTests.swift -o .build/http-tests
.build/http-tests "http://127.0.0.1:$(cat "$port_file")"
