#!/bin/sh
# Wraps `swift test` with the flags required to find Swift Testing's
# framework on a host that has only the standalone Swift toolchain (CLT)
# installed — no full Xcode.
#
# - `-F /Library/Developer/CommandLineTools/Library/Developer/Frameworks`
#   makes `import Testing` resolve.
# - `-Xfrontend -disable-cross-import-overlays` avoids the broken
#   `_Testing_Foundation` cross-import overlay shipped with CLT.
# - `-Xlinker -rpath ...` ensures `Testing.dylib` is loadable at runtime.
#
# On a developer Mac with full Xcode these flags are harmless extras.
#
# Usage:
#   scripts/swift-test.sh [extra args forwarded to `swift test`]
#
set -eu

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks

exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$FW" \
    "$@"
