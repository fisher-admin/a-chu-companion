#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./sign-app.sh --check
python3 - "$PWD" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])
executables = {str(root / "dist/A畜伴侣.app/Contents/MacOS/AChuCompanion"),
               str(Path.home() / "Applications/A畜伴侣.app/Contents/MacOS/AChuCompanion")}
output = subprocess.run(["/bin/ps", "-axo", "pid,comm"], capture_output=True, text=True, check=True).stdout
for line in output.splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) == 2 and fields[1] in executables:
        pid = int(fields[0])
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
        for _ in range(50):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Please quit A畜伴侣 before installing; current application was left in place")
PY
./build.sh
python3 - "$PWD" <<'PY'
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
applications = Path.home() / "Applications"
applications.mkdir(exist_ok=True)
destination = applications / "A畜伴侣.app"
if destination.exists():
    info = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.achu.companion":
        raise RuntimeError("An unrelated application already occupies the install path")
with tempfile.TemporaryDirectory(prefix=".achu-install-", dir=applications) as directory:
    temporary = Path(directory)
    staged = temporary / "A畜伴侣.app"
    previous = temporary / "previous.app"
    shutil.copytree(root / "dist/A畜伴侣.app", staged)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(staged)], check=True)
    if destination.exists():
        output = subprocess.run(["/usr/bin/codesign", "-d", "-r-", str(destination)], capture_output=True, text=True, check=True)
        rule = next((line.removeprefix("designated => ") for line in (output.stdout + output.stderr).splitlines() if line.startswith("designated => ")), None)
        if rule is None:
            raise RuntimeError("Existing installation lacks the fixed identity; refusing to silently replace its authorization")
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + rule, str(staged)], check=True)
        destination.rename(previous)
    try:
        staged.rename(destination)
    except OSError:
        if previous.exists():
            previous.rename(destination)
        raise
registration_tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
subprocess.run([registration_tool, "-u", str(root / "dist/A畜伴侣.app")], capture_output=True)
subprocess.run([registration_tool, "-f", str(destination)], check=True)
subprocess.run(["/usr/bin/mdimport", "-i", str(destination)], check=True)
print(f"Installed: {destination}")
PY
