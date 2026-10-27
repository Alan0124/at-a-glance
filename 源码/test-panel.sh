#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
test_binary="$(mktemp -d /tmp/ataglance-panel.XXXXXX)"
trap 'rm -rf "$test_binary"' EXIT
swiftc -swift-version 5 -target arm64-apple-macosx13.0 -parse-as-library -D PANEL_TESTS Sources/*.swift Tests/PanelTests.swift -o "$test_binary/panel-tests"
"$test_binary/panel-tests"
