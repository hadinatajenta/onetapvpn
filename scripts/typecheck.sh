#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILES=()
while IFS= read -r file; do
    FILES+=("$file")
done < <(find Sources -name '*.swift' -print | sort)

swiftc -typecheck -swift-version 5 "${FILES[@]}" \
    -framework AppKit \
    -framework AVFoundation \
    -framework SwiftUI \
    -framework Combine \
    -framework Security \
    -framework CryptoKit
