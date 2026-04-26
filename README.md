# ExpresScan (iOS) — Core Swift Package

This repo holds the iOS app for ExpresScan: a SwiftUI client that turns an
iPhone into an NFC card reader for ExpresSync. The repo is split in two:

- **`Package.swift` + `Sources/` + `Tests/`** — pure-Swift libraries
  (`Models`, `Crypto`, `Networking`, `AuthCore`) that build via SwiftPM
  and unit-test on any macOS host. No UIKit / SwiftUI / CoreNFC.
- **`App/`** *(future, owned by tracks E-app-skel + E-app-wire)* — the
  SwiftUI app target, code-signed and built via xcodegen on a developer
  machine with full Xcode.

## Run the tests

On a host with **full Xcode** installed:

```bash
swift test
```

On a host with only the **standalone Swift toolchain (CLT)** — no full
Xcode — `swift test` cannot find the Swift Testing framework on its own.
Use either of:

```bash
scripts/swift-test.sh                                 # wrapper
swift test --toolset scripts/clt-toolset.json         # equivalent
```

The wrapper passes the `-F`/`-rpath`/cross-import-overlay flags Swift
needs to load `Testing.framework` from
`/Library/Developer/CommandLineTools/Library/Developer/Frameworks`.

The suite includes:

- `ScanResultSignerTests` — HMAC-SHA256 known-vector check (vectors
  cross-checked with the backend repo).
- `HexEncodingTests` — round-trip hex encode/decode.
- `ContractRoundTripTests` — Codable mirrors of the canonical TS types
  in `docs/plan/20-contracts.md` decode/encode without drift.
- `APIClientTests` — `URLProtocol` stub asserts the status-code →
  `APIError` mapping, bearer/idempotency header rules.
- `SSELineParserTests` — the SSE byte parser's line / event semantics.
- `AuthStoreTests` — Keychain round-trip on a unique-per-run service id.
  These tests auto-skip on hosts where the test binary has no
  `application-identifier` entitlement (raw `swift test` on CLT) and run
  end-to-end on properly code-signed builds.

## Plan documents

The full design lives in `docs/plan/`. Start at `00-overview.md`.

## What is **not** here yet

The SwiftUI app target (`App/…`), `Info.plist`, asset catalog, entitlements,
and `project.yml` for xcodegen all land in Wave 3 (E-app-skel) and Wave 4
(E-app-wire). There is no `.xcodeproj` in the repo — it is regenerated
from `project.yml` on a developer Mac.
