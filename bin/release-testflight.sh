#!/usr/bin/env bash
# release-testflight.sh — one-shot TestFlight release driver.
#
# What it does, in order:
#   1. Bump CURRENT_PROJECT_VERSION + CFBundleVersion in project.yml
#      (monotonic int; reads the current value and adds 1).
#   2. Regenerate the .xcodeproj via xcodegen.
#   3. Archive ExpresScan-Release config for generic iOS device.
#   4. Export the archive with method=app-store-connect, destination=upload.
#      Manual signing using the App Store distribution profile created via
#      the ASC API (see ~/.claude/plans for the original setup).
#   5. Poll App Store Connect until the newly-uploaded build is VALID
#      (5-15 min typical).
#   6. Launch TestFlight on the connected dev iPhone so the user can
#      tap "Update" on the app row. (Both dev + TF builds share bundle
#      ID `express.polaris.ios`, so the TF install replaces the dev
#      build in place — no uninstall needed.)
#
# Prerequisites — one-time setup (already done in the original session):
#   - ~/.secrets/expressync/AuthKey_3QASFD6K93.p8 (ASC API key)
#   - Apple Distribution cert in login keychain (`security find-identity -v`)
#   - Provisioning profile "express polaris ios App Store (claude)"
#     under ~/Library/Developer/Xcode/UserData/Provisioning Profiles/
#   - xcodegen + librsvg + deno on PATH
#   - Xcode-beta installed at /Applications/Xcode-beta.app
#
# Usage:
#   bin/release-testflight.sh                # full pipeline
#   bin/release-testflight.sh --skip-bump    # use the current build number as-is
#   bin/release-testflight.sh --skip-device  # don't touch the iPhone

set -euo pipefail

# --- Config -----------------------------------------------------------------
TEAM_ID="48H7CLBV8Y"
BUNDLE_ID="express.polaris.ios"
PROFILE_NAME="express polaris ios App Store (claude)"

ASC_API_KEY_PATH="$HOME/.secrets/expressync/AuthKey_3QASFD6K93.p8"
ASC_API_KEY_ID="3QASFD6K93"
ASC_API_ISSUER_ID="69a6de71-4cb4-47e3-e053-5b8c7c11a4d1"
ASC_APP_ID="6766818991"

DEVELOPER_DIR_OVERRIDE="/Applications/Xcode-beta.app/Contents/Developer"
DEVICE_ID="984F8C13-6E62-5A85-A9CC-8AFC97AC1CC9"   # Vladosaurus

# --- Args -------------------------------------------------------------------
SKIP_BUMP=0
SKIP_DEVICE=0
for arg in "$@"; do
  case "$arg" in
    --skip-bump) SKIP_BUMP=1 ;;
    --skip-device) SKIP_DEVICE=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# --- Locate repo root + tools ----------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DENO_BIN="${DENO_BIN:-$HOME/.deno/bin/deno}"
[[ -x "$DENO_BIN" ]] || { echo "deno not found at $DENO_BIN — set DENO_BIN env var"; exit 1; }
command -v xcodegen >/dev/null || { echo "xcodegen not on PATH"; exit 1; }
[[ -f "$ASC_API_KEY_PATH" ]] || { echo "missing ASC API key at $ASC_API_KEY_PATH"; exit 1; }

# --- 1. Bump build number ---------------------------------------------------
if [[ "$SKIP_BUMP" == 0 ]]; then
  CURRENT=$(grep -oE 'CURRENT_PROJECT_VERSION: "[0-9]+"' project.yml | head -1 | grep -oE '[0-9]+')
  [[ -n "$CURRENT" ]] || { echo "could not read CURRENT_PROJECT_VERSION from project.yml"; exit 1; }
  NEXT=$((CURRENT + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT\"/CURRENT_PROJECT_VERSION: \"$NEXT\"/" project.yml
  sed -i '' "s/CFBundleVersion: \"$CURRENT\"/CFBundleVersion: \"$NEXT\"/" project.yml
  echo "→ bumped build $CURRENT → $NEXT"
else
  NEXT=$(grep -oE 'CURRENT_PROJECT_VERSION: "[0-9]+"' project.yml | head -1 | grep -oE '[0-9]+')
  echo "→ using existing build $NEXT (--skip-bump)"
fi

# --- 2. Regenerate project --------------------------------------------------
xcodegen generate >/dev/null
echo "→ regenerated .xcodeproj"

# --- 3. Archive -------------------------------------------------------------
ARCHIVE="/tmp/ExpresScan-${NEXT}.xcarchive"
rm -rf "$ARCHIVE"
echo "→ archiving Release ($ARCHIVE)…"
DEVELOPER_DIR="$DEVELOPER_DIR_OVERRIDE" xcodebuild \
    -project ExpresScan.xcodeproj \
    -scheme ExpresScan-Release \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_API_KEY_PATH" \
    -authenticationKeyID "$ASC_API_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_API_ISSUER_ID" \
    archive >/tmp/release-archive.log 2>&1 \
  || { echo "archive failed; tail of /tmp/release-archive.log:"; tail -30 /tmp/release-archive.log; exit 1; }
echo "  ✓ archive succeeded"

# --- 4. Export + upload -----------------------------------------------------
EXPORT_OPTS=$(mktemp -t expresscharge-export.plist)
cat > "$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_ID</key>
    <string>$PROFILE_NAME</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
EOF

EXPORT_DIR="/tmp/ExpresScan-${NEXT}-export"
rm -rf "$EXPORT_DIR"
echo "→ uploading to App Store Connect…"
DEVELOPER_DIR="$DEVELOPER_DIR_OVERRIDE" xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -authenticationKeyPath "$ASC_API_KEY_PATH" \
    -authenticationKeyID "$ASC_API_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_API_ISSUER_ID" >/tmp/release-export.log 2>&1 \
  || { echo "export failed; tail of /tmp/release-export.log:"; tail -30 /tmp/release-export.log; exit 1; }
echo "  ✓ upload succeeded"

# --- 5. Wait for processing -------------------------------------------------
echo "→ waiting for App Store Connect to finish processing build $NEXT…"
ASC_API_KEY_PATH="$ASC_API_KEY_PATH" \
ASC_API_KEY_ID="$ASC_API_KEY_ID" \
ASC_API_ISSUER_ID="$ASC_API_ISSUER_ID" \
ASC_APP_ID="$ASC_APP_ID" \
"$DENO_BIN" run \
    --allow-read="$ASC_API_KEY_PATH" \
    --allow-env=ASC_API_KEY_PATH,ASC_API_KEY_ID,ASC_API_ISSUER_ID,ASC_APP_ID \
    --allow-net=api.appstoreconnect.apple.com \
    bin/asc-wait-for-build.ts "$NEXT"
echo "  ✓ build $NEXT is VALID"

# --- 5b. Auto-fill "What to Test" from commits since the last build bump ---
# Walks git history backwards from HEAD looking for the previous commit
# that touched CURRENT_PROJECT_VERSION in project.yml. Everything since
# is what changed in this build. Strips bump/release commits themselves
# and lines starting with "Co-Authored-By:" so the note reads cleanly.
echo "→ generating What to Test from git log…"
PREV_BUMP=$(git log --pretty=%H -- project.yml | xargs -I{} git show --quiet --pretty=%H {} -- project.yml \
  2>/dev/null | head -2 | tail -1) || PREV_BUMP=""
if [[ -z "$PREV_BUMP" ]]; then
  RANGE_DESC="all commits"
  COMMITS=$(git log --pretty='format:%s' -50 -- . ':!bin/release-testflight.sh' ':!bin/asc-*.ts')
else
  RANGE_DESC="$PREV_BUMP..HEAD"
  COMMITS=$(git log "${PREV_BUMP}..HEAD" --pretty='format:%s' -- . ':!bin/release-testflight.sh' ':!bin/asc-*.ts')
fi
WHATS_NEW=$(echo "$COMMITS" \
  | grep -vE '^(chore|release|bump)\(?.*\)?:.*build|^Bump|^Release ' \
  | grep -vE '^Co-Authored-By:' \
  | sed -E 's/^/• /' \
  | head -20)
if [[ -z "$WHATS_NEW" ]]; then
  WHATS_NEW="• Build $NEXT — internal dogfood release."
fi
echo "  range: $RANGE_DESC"
echo "$WHATS_NEW" | sed 's/^/    /'
ASC_API_KEY_PATH="$ASC_API_KEY_PATH" \
ASC_API_KEY_ID="$ASC_API_KEY_ID" \
ASC_API_ISSUER_ID="$ASC_API_ISSUER_ID" \
ASC_APP_ID="$ASC_APP_ID" \
"$DENO_BIN" run \
    --allow-read="$ASC_API_KEY_PATH" \
    --allow-env=ASC_API_KEY_PATH,ASC_API_KEY_ID,ASC_API_ISSUER_ID,ASC_APP_ID \
    --allow-net=api.appstoreconnect.apple.com \
    bin/asc-set-whats-new.ts "$NEXT" "$WHATS_NEW"

# --- 6. Prompt the device --------------------------------------------------
if [[ "$SKIP_DEVICE" == 0 ]]; then
  echo "→ launching TestFlight on Vladosaurus so you can tap Update…"
  if DEVELOPER_DIR="$DEVELOPER_DIR_OVERRIDE" xcrun devicectl list devices 2>/dev/null \
       | grep -q "$DEVICE_ID"; then
    DEVELOPER_DIR="$DEVELOPER_DIR_OVERRIDE" xcrun devicectl device process launch \
        --device "$DEVICE_ID" com.apple.TestFlight 2>&1 \
      | tail -2 \
      || echo "  (could not launch TestFlight remotely — open it manually on the device)"
  else
    echo "  device $DEVICE_ID not connected — skipping launch step"
  fi
fi

echo
echo "✓ build $NEXT shipped to TestFlight"
echo "  app:    https://appstoreconnect.apple.com/apps/$ASC_APP_ID/testflight/ios"
echo "  on iPhone: tap Update next to ExpressCharge in the TestFlight app"
