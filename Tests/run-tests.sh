#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build
cp Tests/TOTPTests.swift build/main.swift

swiftc -swift-version 5 \
    Sources/Shared/Models.swift \
    Sources/Shared/Protocols.swift \
    Sources/Core/Base32.swift \
    Sources/Core/TOTPGenerator.swift \
    build/main.swift \
    -o build/totp-tests \
    -framework CryptoKit

./build/totp-tests
