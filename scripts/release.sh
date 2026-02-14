#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, and package NoteTaker as a DMG.
#
# Required env vars:
#   TEAM_ID              — Apple Developer Team ID
#   APPLE_ID             — Apple ID email for notarization
#   APP_SPECIFIC_PASSWORD — App-specific password (appleid.apple.com > Sign-In and Security > App-Specific Passwords)
#
# Optional env vars:
#   VERSION       — e.g. "1.0.0", updates CFBundleShortVersionString in Info.plist
#   BUILD_NUMBER  — explicit build number, otherwise auto-increments current value
#   OUTPUT_DIR    — output directory (default: build/release)

set -euo pipefail

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step_num=0
step() {
    step_num=$((step_num + 1))
    echo ""
    echo -e "${BLUE}━━━ Step ${step_num}: $1 ━━━${NC}"
}

success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# Trap errors and report which step failed
trap 'echo ""; echo -e "${RED}✗ Release failed at step ${step_num}${NC}"; exit 1' ERR

# ---------- Configuration ----------
APP_NAME="NoteTaker"
SCHEME="NoteTaker"
PROJECT="${APP_NAME}.xcodeproj"
PLIST="Resources/Info.plist"
OUTPUT_DIR="${OUTPUT_DIR:-build/release}"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"

# Move to repo root (script may be invoked from anywhere)
cd "$(dirname "$0")/.."

# ========== Step 1: Validate env vars ==========
step "Validate environment"

missing=()
[ -z "${TEAM_ID:-}" ]              && missing+=("TEAM_ID")
[ -z "${APPLE_ID:-}" ]             && missing+=("APPLE_ID")
[ -z "${APP_SPECIFIC_PASSWORD:-}" ] && missing+=("APP_SPECIFIC_PASSWORD")

if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Missing required environment variables:${NC}"
    for var in "${missing[@]}"; do
        echo "  - ${var}"
    done
    echo ""
    echo "Usage:"
    echo "  TEAM_ID=XXXXXXXXXX \\"
    echo "  APPLE_ID=you@example.com \\"
    echo "  APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \\"
    echo "  ./scripts/release.sh"
    echo ""
    echo "To get an app-specific password:"
    echo "  1. Go to https://appleid.apple.com"
    echo "  2. Sign-In and Security → App-Specific Passwords"
    echo "  3. Generate a new password for 'NoteTaker Release'"
    echo ""
    echo "To find your Team ID:"
    echo "  1. Go to https://developer.apple.com/account"
    echo "  2. Membership Details → Team ID"
    exit 1
fi

success "All required env vars set"

# ========== Step 2: Check tools ==========
step "Check required tools"

command -v xcodegen >/dev/null 2>&1 || fail "xcodegen not found. Install with: brew install xcodegen"
success "xcodegen found"

command -v xcrun >/dev/null 2>&1 || fail "xcrun not found. Install Xcode Command Line Tools."
xcrun notarytool --version >/dev/null 2>&1 || fail "notarytool not available. Requires Xcode 13+."
success "xcrun notarytool found"

# Check for Developer ID signing identity
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
if [ -z "$SIGNING_IDENTITY" ]; then
    fail "No 'Developer ID Application' certificate found in keychain.
  See: https://developer.apple.com/help/account/certificates/create-developer-id-certificates"
fi
success "Signing identity: ${SIGNING_IDENTITY}"

HAS_XCPRETTY=false
if command -v xcpretty >/dev/null 2>&1; then
    HAS_XCPRETTY=true
    success "xcpretty found (will use for cleaner output)"
else
    warn "xcpretty not found (raw xcodebuild output will be shown)"
fi

# ========== Step 3: Version bump (optional) ==========
step "Version"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
    success "Version set to ${VERSION} (was ${CURRENT_VERSION})"
    CURRENT_VERSION="$VERSION"
else
    success "Version: ${CURRENT_VERSION} (unchanged)"
fi

if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PLIST"
    success "Build number set to ${BUILD_NUMBER}"
    CURRENT_BUILD="$BUILD_NUMBER"
else
    NEW_BUILD=$((CURRENT_BUILD + 1))
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$PLIST"
    success "Build number auto-incremented: ${CURRENT_BUILD} → ${NEW_BUILD}"
    CURRENT_BUILD="$NEW_BUILD"
fi

# ========== Step 4: Generate Xcode project ==========
step "Generate Xcode project"

xcodegen generate --quiet
success "Xcode project generated"

# ========== Step 5: Archive ==========
step "Archive"

ARCHIVE_CMD=(
    xcodebuild archive
    -project "$PROJECT"
    -scheme "$SCHEME"
    -archivePath "$ARCHIVE_PATH"
    CODE_SIGN_IDENTITY="Developer ID Application"
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_STYLE="Manual"
    -quiet
)

if [ "$HAS_XCPRETTY" = true ]; then
    # Remove -quiet and pipe through xcpretty
    ARCHIVE_CMD=("${ARCHIVE_CMD[@]/-quiet/}")
    "${ARCHIVE_CMD[@]}" 2>&1 | xcpretty
else
    "${ARCHIVE_CMD[@]}"
fi

[ -d "$ARCHIVE_PATH" ] || fail "Archive not found at $ARCHIVE_PATH"
success "Archive created"

# ========== Step 6: Generate ExportOptions.plist ==========
step "Generate ExportOptions.plist"

EXPORT_OPTIONS="build/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

success "ExportOptions.plist written"

# ========== Step 7: Export signed app ==========
step "Export signed app"

EXPORT_CMD=(
    xcodebuild -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$EXPORT_PATH"
    -exportOptionsPlist "$EXPORT_OPTIONS"
    -quiet
)

if [ "$HAS_XCPRETTY" = true ]; then
    EXPORT_CMD=("${EXPORT_CMD[@]/-quiet/}")
    "${EXPORT_CMD[@]}" 2>&1 | xcpretty
else
    "${EXPORT_CMD[@]}"
fi

APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
[ -d "$APP_PATH" ] || fail "Exported app not found at $APP_PATH"
success "App exported and signed"

# ========== Step 8: Create DMG ==========
step "Create DMG"

mkdir -p "$OUTPUT_DIR"
DMG_NAME="${APP_NAME}-${CURRENT_VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

# Remove existing DMG if present
rm -f "$DMG_PATH"

# Create a temporary directory for DMG contents
DMG_STAGING="build/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    -quiet

rm -rf "$DMG_STAGING"

[ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH"
success "DMG created: ${DMG_PATH}"

# ========== Step 9: Notarize ==========
step "Notarize DMG"

echo "  Submitting to Apple (this may take a few minutes)..."

xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

success "Notarization complete"

# ========== Step 10: Staple ==========
step "Staple notarization ticket"

xcrun stapler staple "$DMG_PATH"
success "Ticket stapled to DMG"

# ========== Summary ==========
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
DMG_SHA=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo -e "${GREEN}━━━ Release Complete ━━━${NC}"
echo ""
echo "  App:       ${APP_NAME}"
echo "  Version:   ${CURRENT_VERSION} (${CURRENT_BUILD})"
echo "  DMG:       ${DMG_PATH}"
echo "  Size:      ${DMG_SIZE}"
echo "  SHA-256:   ${DMG_SHA}"
echo ""
echo -e "  Verify:    ${YELLOW}spctl --assess --type open --context context:primary-signature ${DMG_PATH}${NC}"
echo ""
