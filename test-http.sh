#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
port_file=$(mktemp /private/tmp/achu-port.XXXXXX)
python3 Tests/MockServer.py "$port_file" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
for attempt in {1..30}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    print -u2 'Local HTTP fixture could not start; tests stopped.'
    exit 1
  fi
  [[ -s "$port_file" ]] && break
  sleep 0.1
done
if [[ ! -s "$port_file" ]]; then
  print -u2 'Local HTTP fixture did not provide a port; tests stopped.'
  exit 1
fi
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/TextTranslation.swift Tests/HTTPTests.swift -o .build/http-tests
.build/http-tests "http://127.0.0.1:$(cat "$port_file")"
