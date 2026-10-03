#!/bin/zsh
set -euo pipefail
python3 - <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

NAME = "AChuCompanion Local Signing"
support = Path.home() / "Library/Application Support/AChuCompanion"
config_file = support / "signing.json"


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"Command failed: {args[0]}")
    return result.stdout


def fingerprint(certificate):
    value = run("/usr/bin/openssl", "x509", "-in", str(certificate), "-noout", "-fingerprint", "-sha1")
    digest = value.strip().split("=", 1)[1].replace(":", "").upper()
    if not re.fullmatch(r"[0-9A-F]{40}", digest):
        raise RuntimeError("Invalid certificate fingerprint")
    return digest


os.umask(0o077)
support.mkdir(parents=True, exist_ok=True)
keychain = run("/usr/bin/security", "default-keychain", "-d", "user").strip().strip('"')
with tempfile.TemporaryDirectory(prefix="achu-signing-setup-") as directory:
    temporary = Path(directory)
    certificate = temporary / "certificate.pem"
    if config_file.exists():
        config = json.loads(config_file.read_text())
        identity, keychain = config["sha1"], config["keychain"]
        if not re.fullmatch(r"[0-9A-F]{40}", identity):
            raise RuntimeError("Invalid existing signing configuration; refusing to replace it")
        identities = run("/usr/bin/security", "find-identity", "-p", "codesigning", keychain)
        if identity not in identities:
            raise RuntimeError("Original signing private key is missing; refusing to create a new identity")
        print("Reusing original local signing identity")
    else:
        existing = subprocess.run(["/usr/bin/security", "find-certificate", "-c", NAME, "-p", keychain], capture_output=True, text=True)
        if existing.returncode == 0:
            certificate.write_text(existing.stdout)
            identity = fingerprint(certificate)
            identities = run("/usr/bin/security", "find-identity", "-p", "codesigning", keychain)
            if identity not in identities:
                raise RuntimeError("Existing certificate has no available private key; refusing to replace it")
            print("Recovered original local signing identity")
        elif existing.returncode == 44:
            private_key = temporary / "private-key.pem"
            settings = temporary / "certificate.cnf"
            settings.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = AChuCompanion Local Signing
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
            run("/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256", "-days", "3650",
                "-config", str(settings), "-keyout", str(private_key), "-out", str(certificate))
            aggregate = temporary / "identity.pem"
            aggregate.write_bytes(private_key.read_bytes() + certificate.read_bytes())
            run("/usr/bin/security", "import", str(aggregate), "-k", keychain, "-t", "agg", "-f", "pemseq", "-x", "-T", "/usr/bin/codesign")
            identity = fingerprint(certificate)
            print("Created dedicated local signing identity; private key is nonextractable in the login Keychain")
        else:
            raise RuntimeError(existing.stderr.strip() or "Certificate lookup failed; refusing to create a replacement")

    probe = temporary / "signing-check"
    shutil.copyfile("/usr/bin/true", probe)
    probe.chmod(0o700)
    requirement = f'designated => identifier "local.achu.signingcheck" and certificate leaf = H"{identity}"'
    run("/usr/bin/codesign", "--force", "--identifier", "local.achu.signingcheck", "--sign", identity,
        "--keychain", keychain, "--timestamp=none", "--requirements", "=" + requirement, str(probe))
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + requirement.removeprefix("designated => "), str(probe))
    if not config_file.exists():
        config_file.write_text(json.dumps({"sha1": identity, "keychain": keychain}, indent=2) + "\n")
        config_file.chmod(0o600)
    print("PASS: fixed local signing configured and verified; no system trust settings changed")
PY
