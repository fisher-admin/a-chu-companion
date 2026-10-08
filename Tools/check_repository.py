#!/usr/bin/env python3
"""Validate public repository files without printing credential contents."""

import argparse
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


REQUIRED = (
    "README.md", "README.en.md", "LICENSE", "CHANGELOG.md", "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md", "SECURITY.md", "SUPPORT.md", "docs/PRIVACY.md",
    "docs/maintainers/RELEASING.md", "docs/DEVELOPMENT_HISTORY.zh-CN.md",
    ".editorconfig", ".gitattributes", ".github/CODEOWNERS",
    ".github/ISSUE_TEMPLATE/config.yml", ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/feature_request.yml", ".github/pull_request_template.md",
    ".github/dependabot.yml", ".github/release.yml", ".github/workflows/ci.yml", ".github/workflows/codeql.yml",
)
# These exact synthetic sessions are used only by mock request/decryption tests.
DUMMY = {
    "Tests/UsageTests.swift": {"sk-ant-" + "sid01-testonlyabcdefghijklmnop"},
    "Tests/UsageMonitorTests.swift": {"sk-ant-" + "sid01-fixtureonlyabcdefghijklmnop"},
    "Tests/FidelityFallbackTests.swift": {"sk-ant-" + "sid01-fixtureonlyabcdefghijklmnop"},
}
PATTERNS = (
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}(?![0-9A-Za-z_-])")),
    ("Claude session", re.compile(r"sk-ant-sid\d+-[A-Za-z0-9_-]{8,}")),
    ("Anthropic API key", re.compile(r"sk-ant-api\d+-[A-Za-z0-9_-]{16,}")),
    ("GitHub token", re.compile(r"(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
    ("OpenAI key", re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{30,}")),
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
)


def credential_kinds(path, content):
    findings = []
    allowed = DUMMY.get(path, set())
    for kind, pattern in PATTERNS:
        for match in pattern.finditer(content):
            token = match.group()
            # Provider-specific patterns are reported once under their own name.
            if kind == "OpenAI key" and token.startswith("sk-ant-"):
                continue
            if token not in allowed:
                findings.append(kind)
                break
    return findings


def broken_links(root, path, content):
    failures = []
    for target in re.findall(r"!?\[[^\]]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)", content):
        target = target.strip("<>")
        parts = urlsplit(target)
        if parts.scheme or parts.netloc or not parts.path:
            continue
        local = (root / path).parent / unquote(parts.path)
        try:
            local.resolve().relative_to(root.resolve())
        except ValueError:
            failures.append(target)
            continue
        if not local.exists():
            failures.append(target)
    return failures


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def check(root, history=False):
    failures = []
    for path in REQUIRED:
        if not (root / path).is_file() or not (root / path).stat().st_size:
            failures.append("Missing required file: " + path)
    files = git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z").decode().split("\0")
    checked = 0
    for path in filter(None, files):
        file = root / path
        if not file.is_file():
            continue
        checked += 1
        content = file.read_bytes().decode("utf-8", errors="replace")
        for kind in credential_kinds(path, content):
            failures.append("Credential pattern (" + kind + "): " + path)
        if path.endswith(".md"):
            for target in broken_links(root, path, content):
                failures.append("Broken local link: " + path + " -> " + target)
    workflows = root / ".github/workflows"
    for path in workflows.glob("*.yml"):
        content = path.read_text()
        for action in re.findall(r"\buses:\s*([^\s#]+)", content):
            if not action.startswith("./") and not re.fullmatch(r"[^@]+@[0-9a-f]{40}", action):
                failures.append("Action is not SHA-pinned: " + path.name)
        if "pull_request_target:" in content:
            failures.append("Privileged PR workflow requires separate review: " + path.name)
    blobs = 0
    if history:
        for line in git(root, "rev-list", "--objects", "--all").decode().splitlines():
            oid, _, path = line.partition(" ")
            if git(root, "cat-file", "-t", oid).strip() != b"blob":
                continue
            blobs += 1
            content = git(root, "cat-file", "blob", oid).decode("utf-8", errors="replace")
            for kind in credential_kinds(path, content):
                failures.append("Historical credential pattern (" + kind + "): " + path + " [" + oid[:12] + "]")
    for failure in failures:
        print("FAIL: " + failure, file=sys.stderr)
    if not failures:
        print("PASS: repository files, local documentation links, pinned actions and credential patterns")
    print("Files checked: " + str(checked) + "; historical blobs checked: " + str(blobs))
    print("Pattern checks supplement GitHub secret scanning; they do not prove every possible secret is absent.")
    return not failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true", help="Also inspect all locally available Git history")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    return 0 if check(root, args.history) else 1


if __name__ == "__main__":
    sys.exit(main())
