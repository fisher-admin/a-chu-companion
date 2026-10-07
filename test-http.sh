#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
port_file=$(mktemp /private/tmp/achu-port.XXXXXX)
server_log="$PWD/.build/http-fixture.log"
python3 -u Tests/MockServer.py "$port_file" > "$server_log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
# A clean runner can need more than three seconds to start Python and bind.
# Stop immediately if the process exits; otherwise allow up to thirty seconds.
for attempt in {1..300}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    print -u2 'Local HTTP fixture could not start; tests stopped.'
    cat "$server_log" >&2
    exit 1
  fi
  [[ -s "$port_file" ]] && break
  sleep 0.1
done
if [[ ! -s "$port_file" ]]; then
  print -u2 'Local HTTP fixture did not provide a port within 30 seconds; tests stopped.'
  cat "$server_log" >&2
  exit 1
fi
swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" Sources/Core.swift Sources/GeminiTranslation.swift Sources/TextTranslation.swift Sources/TranslationFidelity.swift Sources/TranslationStructure.swift Sources/MarkdownTable.swift Tests/HTTPTests.swift -o .build/http-tests
.build/http-tests "http://127.0.0.1:$(cat "$port_file")"
