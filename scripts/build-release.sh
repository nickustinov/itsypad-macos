#!/bin/bash
set -e

# Configuration
APP_NAME="itsypad"
VERSION=$(grep 'MARKETING_VERSION:' project.yml | grep -v CFBundle | sed 's/.*: *"\(.*\)"/\1/')
SIGNING_IDENTITY="Developer ID Application"

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/itsypad.xcarchive"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

cd "$PROJECT_DIR"
mkdir -p "$DIST_DIR"

echo "==> Version: $VERSION"

# Find Developer ID provisioning profile
PROFILE_PATH=$(find ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles -name "*.provisionprofile" -exec sh -c 'security cms -D -i "$1" 2>/dev/null | grep -q "Itsypad Developer ID" && echo "$1"' _ {} \;)
if [ -z "$PROFILE_PATH" ]; then
    echo "ERROR: 'Itsypad Developer ID' provisioning profile not found."
    echo "Download it from developer.apple.com and double-click to install."
    exit 1
fi
echo "==> Profile: $PROFILE_PATH"

# Generate Xcode project from project.yml
echo "==> Generating Xcode project..."
xcodegen generate

# Archive without signing (avoids profile conflicts with dependencies)
echo "==> Archiving..."
xcodebuild -scheme itsypad -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/Itsypad.app"

# Embed provisioning profile
echo "==> Embedding provisioning profile..."
cp "$PROFILE_PATH" "$ARCHIVE_APP/Contents/embedded.provisionprofile"

# Sign frameworks and dylibs first
echo "==> Signing with Developer ID..."
find "$ARCHIVE_APP" \( -name "*.framework" -o -name "*.dylib" \) | while read -r item; do
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$item"
done

# Create resolved entitlements (Xcode variables aren't available during manual signing)
RESOLVED_ENTITLEMENTS="$DIST_DIR/itsypad-resolved.entitlements"
sed -e 's/$(TeamIdentifierPrefix)/R892A93W42./g' \
    -e 's/$(CFBundleIdentifier)/com.nickustinov.itsypad/g' \
    "$PROJECT_DIR/Sources/itsypad.entitlements" > "$RESOLVED_ENTITLEMENTS"

# Sign the app bundle with resolved entitlements
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements "$RESOLVED_ENTITLEMENTS" \
    "$ARCHIVE_APP"
rm "$RESOLVED_ENTITLEMENTS"

# Extract signed app
echo "==> Extracting app bundle..."
rm -rf "$APP_BUNDLE"
cp -R "$ARCHIVE_APP" "$APP_BUNDLE"
rm -rf "$ARCHIVE_PATH"

# Verify
echo "==> Checking architectures..."
lipo -info "$APP_BUNDLE/Contents/MacOS/Itsypad"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE"

# Create DMG
echo "==> Creating DMG..."
rm -f "$DMG_PATH"
DMG_STAGING="$DIST_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "==> Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo "==> Build complete!"
echo "    App: $APP_BUNDLE"
echo "    DMG: $DMG_PATH"
echo "    SHA256: $SHA256"
echo ""
echo "To notarize, run:"
echo "    xcrun notarytool submit \"$DMG_PATH\" --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD> --wait"
echo "    xcrun stapler staple \"$DMG_PATH\""
echo ""
echo "To create a GitHub release:"
echo "    gh release create v$VERSION \"$DMG_PATH\" --title \"v$VERSION\" --generate-notes"
echo ""
echo "To update Homebrew tap (after notarizing and uploading to GitHub):"
echo "    1. Get SHA256 of the NOTARIZED DMG: shasum -a 256 \"$DMG_PATH\""
echo "    2. Update Casks/itsypad.rb in homebrew-tap with version \"$VERSION\" and new sha256"
echo "    3. Commit and push the tap"
