#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$PWD/build/module-cache" \
  Sources/HistoryStore.swift Sources/SearchModel.swift Tests/HistoryStoreTests.swift \
  -lsqlite3 -o build/HistoryStoreTests
build/HistoryStoreTests
