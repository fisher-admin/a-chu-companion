#!/bin/zsh
set -euo pipefail
python3 - "$@" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

config_path = Path(os.environ.get("ACHU_SIGNING_CONFIG", str(Path.home() / "Library/Application Support/AChuCompanion/signing.json")))
try:
    config = json.loads(config_path.read_text())
    identity, keychain = config["sha1"], config["keychain"]
    if not re.fullmatch(r"[0-9A-F]{40}", identity) or not isinstance(keychain, str):
        raise ValueError("Invalid signing configuration")
    identities = subprocess.run(["/usr/bin/security", "find-identity", "-p", "codesigning", keychain], capture_output=True, text=True, check=True)
    if identity not in identities.stdout:
        raise ValueError("The original signing certificate and private key are unavailable")
    if sys.argv[1:] == ["--check"]:
        print("Fixed local signing identity ready")
        sys.exit(0)
    if len(sys.argv) != 2:
        raise ValueError("Expected an application bundle path")
    app = Path(sys.argv[1]).resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identifier = info["CFBundleIdentifier"]
    if not re.fullmatch(r"local\.achu\.[A-Za-z0-9.-]+", identifier):
        raise ValueError("Application identity is outside this project")
    requirement = f'designated => identifier "{identifier}" and certificate leaf = H"{identity}"'
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", identity, "--keychain", keychain,
                    "--timestamp=none", "--requirements", "=" + requirement, str(app)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + requirement.removeprefix("designated => "), str(app)], check=True)
except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
    print(f"Signing stopped: {error}. Run ./setup-signing.sh to reuse or configure the original identity; no temporary signing fallback.", file=sys.stderr)
    sys.exit(1)
PY
