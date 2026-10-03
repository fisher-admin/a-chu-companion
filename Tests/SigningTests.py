#!/usr/bin/env python3
"""Check signing continuity with real changed binaries and reject impostors."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
CONFIG = Path.home() / "Library/Application Support/AChuCompanion/signing.json"


def run(*args, expected=0, env=None):
    result = subprocess.run(args, capture_output=True, text=True, env=env)
    assert result.returncode == expected, result.stderr or result.stdout
    return result.stdout + result.stderr


def requirement(app):
    output = run("/usr/bin/codesign", "-d", "-r-", str(app))
    match = re.search(r"^designated => (.+)$", output, re.MULTILINE)
    assert match, "Application still uses an implicit or temporary signing identity"
    rule = match.group(1)
    assert "certificate leaf = H\"" in rule and "cdhash" not in rule, rule
    return rule


def main():
    requirement(ROOT / "dist/A畜伴侣.app")
    config = json.loads(CONFIG.read_text())
    identity = config["sha1"]
    with tempfile.TemporaryDirectory(prefix="achu-signing-test-") as directory:
        temporary = Path(directory)
        apps = []
        for index in range(2):
            app = temporary / f"version-{index}.app"
            executable = app / "Contents/MacOS/Probe"
            executable.parent.mkdir(parents=True)
            source = temporary / f"version-{index}.swift"
            source.write_text(f'import Foundation\nprint("version-{index}")\n')
            run("/usr/bin/swiftc", "-module-cache-path", str(ROOT / ".build/cache"), str(source), "-o", str(executable))
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "local.achu.signingtest", "CFBundleExecutable": "Probe",
                "CFBundleName": "AChuSigningTest", "CFBundlePackageType": "APPL",
            }))
            run(str(ROOT / "sign-app.sh"), str(app))
            run("/usr/bin/codesign", "--verify", "--strict", str(app))
            apps.append(app)

        first_rule, second_rule = map(requirement, apps)
        assert first_rule == second_rule and identity.lower() in first_rule.lower()
        fingerprints = [hashlib.sha256((app / "Contents/MacOS/Probe").read_bytes()).hexdigest() for app in apps]
        assert fingerprints[0] != fingerprints[1], "Test versions must contain different compiled code"
        code_hashes = [re.search(r"CDHash=(\w+)", run("/usr/bin/codesign", "-d", "--verbose=4", str(app))).group(1) for app in apps]
        assert code_hashes[0] != code_hashes[1]
        run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + first_rule, str(apps[1]))
        print("PASS: changed binaries and code hashes retain exactly the same certificate identity")

        impostor = temporary / "impostor.app"
        shutil.copytree(apps[0], impostor)
        run("/usr/bin/codesign", "--force", "--sign", "-", str(impostor))
        result = subprocess.run(["/usr/bin/codesign", "--verify", "-R", "=" + first_rule, str(impostor)], capture_output=True)
        assert result.returncode != 0, "Temporary signatures must not impersonate the authorized application"
        print("PASS: a different signer cannot match the authorized application")

        executable = apps[1] / "Contents/MacOS/Probe"
        with executable.open("ab") as handle:
            handle.write(b"unauthorized modification")
        result = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(apps[1])], capture_output=True)
        assert result.returncode != 0
        print("PASS: tampered application is rejected")

        environment = dict(os.environ, ACHU_SIGNING_CONFIG=str(temporary / "missing.json"))
        result = subprocess.run([str(ROOT / "sign-app.sh"), str(apps[0])], capture_output=True, env=environment)
        assert result.returncode != 0
        assert requirement(apps[0]) == first_rule
        print("PASS: missing signing configuration fails without replacing the existing signature")


if __name__ == "__main__":
    main()
