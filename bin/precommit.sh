#!/usr/bin/env bash
#
# bin/precommit.sh — pre-commit verification for ExpresScan iOS.
#
# Wave 6 / Slice L. The mandate is "everything green before commit /
# push / deploy" but the team chose to defer the GitHub Actions wiring
# to a follow-up PR. Until then, run this script before every commit:
#
#   bin/precommit.sh
#
# What it checks (in order, fail-fast):
#   1. SwiftPM library tests (`swift test`) — pure-Swift modules.
#   2. Banned-imports guard — no UIKit / SwiftUI / CoreNFC / etc. in
#      `Sources/`. Comment in `Package.swift:11` documents the rule;
#      this script enforces it.
#   3. SwiftFormat lint (when installed) — fail on style drift.
#   4. Host-app Xcode tests (`ExpresScanTests`) on the iOS 17/26 sim.
#
# Skip the host-app tests for fast iterations:
#   PRECOMMIT_FAST=1 bin/precommit.sh
#
# Requires Xcode-beta. The wrapper sets DEVELOPER_DIR so CLT-only
# Swift can run the SwiftPM half.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

XCODE_BETA="/Applications/Xcode-beta.app/Contents/Developer"
SIM_DEST="${SIM_DEST:-platform=iOS Simulator,name=iPhone 17,OS=latest}"

step() {
  printf '\n\033[36m▶ %s\033[0m\n' "$1"
}
fail() {
  printf '\n\033[31m✘ %s\033[0m\n' "$1" >&2
  exit 1
}

# 1. SwiftPM library tests — covers Models, Crypto, Networking,
#    AuthCore, Capabilities, DeviceSync.
step "SwiftPM library tests"
if [[ -d "$XCODE_BETA" ]]; then
  DEVELOPER_DIR="$XCODE_BETA" xcrun swift test
else
  bash scripts/swift-test.sh
fi

# 2. Banned-imports guard for `Sources/` purity.
step "Banned-imports guard (no UIKit/SwiftUI/CoreNFC in Sources/)"
if grep -rEn 'import (UIKit|SwiftUI|CoreNFC|UserNotifications|WatchKit|AppKit)' Sources/; then
  fail "Banned import found in Sources/. Move the offending code to App/."
fi

# 3. SwiftFormat (optional — install via `brew install swiftformat`).
if command -v swiftformat >/dev/null 2>&1; then
  step "SwiftFormat lint"
  swiftformat --lint Sources App ExpresScanTests ExpresScanUITests
else
  printf '\033[33m⚠ swiftformat not installed; skipping (brew install swiftformat)\033[0m\n'
fi

# 4. Host-app Xcode tests — ExpresScanTests bundle on the simulator.
if [[ "${PRECOMMIT_FAST:-0}" != "1" ]]; then
  step "Host-app tests (ExpresScanTests on iOS 26 simulator)"
  if [[ ! -d "$XCODE_BETA" ]]; then
    fail "Host-app tests require Xcode-beta at $XCODE_BETA. Skip with PRECOMMIT_FAST=1."
  fi
  DEVELOPER_DIR="$XCODE_BETA" xcodegen generate >/dev/null
  DEVELOPER_DIR="$XCODE_BETA" xcodebuild \
    -project ExpresScan.xcodeproj \
    -scheme ExpresScan-Debug \
    -destination "$SIM_DEST" \
    test -only-testing:ExpresScanTests \
    -quiet \
    | grep -E '(error:|FAIL|Failing tests|Test Suite.*(passed|failed)|Executed [0-9]+ test)' \
    | tail -10
fi

printf '\n\033[32m✓ All pre-commit checks passed.\033[0m\n'
