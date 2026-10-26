#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
test_binary="$(mktemp -d /tmp/ataglance-automation.XXXXXX)"
trap 'rm -rf "$test_binary"' EXIT
swiftc -parse-as-library Sources/Automation.swift Tests/AutomationTests.swift -o "$test_binary/automation-tests"
"$test_binary/automation-tests"
python3 - <<'PY'
import pathlib
import subprocess
import urllib.parse

script = str(pathlib.Path("todo").resolve())
result = subprocess.run([script, "add", " 买 咖啡 & 茶+点心 ", "--category", "life", "--due", "2026-10-28", "--print-url"], check=True, text=True, capture_output=True)
params = urllib.parse.parse_qs(urllib.parse.urlparse(result.stdout.strip()).query)
assert params == {"title": ["买 咖啡 & 茶+点心"], "category": ["life"], "due": ["2026-10-28"]}
assert "%20" in result.stdout and "%26" in result.stdout and "%2B" in result.stdout
for args in (["delete", "x"], ["add", "  ", "--print-url"], ["add", "x", "--due", "2026-02-30", "--print-url"]):
    failed = subprocess.run([script] + args, text=True, capture_output=True)
    assert failed.returncode != 0, args
print("PASS: CLI URL encoding and invalid command/date validation; no application opened")
PY
