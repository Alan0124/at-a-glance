#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
test_binary="$(mktemp -d /tmp/ataglance-models.XXXXXX)"
trap 'rm -rf "$test_binary"' EXIT
swiftc -parse-as-library Sources/Models.swift Tests/ModelTests.swift -o "$test_binary/model-tests"
"$test_binary/model-tests"
