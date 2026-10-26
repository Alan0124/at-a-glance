#!/bin/zsh
set -euo pipefail

SOURCE_ROOT="${0:A:h}"
OUTPUT_DIR="${SOURCE_ROOT:h}"
BUILD_DIR="$SOURCE_ROOT/.build"
APP_NAME="常在待办"
# Sign outside iCloud Desktop: File Provider can reattach Finder metadata
# between xattr cleanup and codesign when the staging bundle lives there.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/AtAGlance.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
FINAL_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

mkdir -p "$BUILD_DIR"
if [[ ! -f "$SOURCE_ROOT/Resources/AppIcon.icns" ]]; then
  /usr/bin/swift "$SOURCE_ROOT/Resources/GenerateIcon.swift" "$SOURCE_ROOT/Resources"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$SOURCE_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$SOURCE_ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

/usr/bin/swiftc \
  -swift-version 5 -parse-as-library -O \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  -framework AppKit -framework SwiftUI -framework Combine \
  -framework ServiceManagement -framework UniformTypeIdentifiers -framework Carbon \
  "$SOURCE_ROOT"/Sources/*.swift \
  -o "$APP_BUNDLE/Contents/MacOS/AtAGlance"

/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

# Keep the previous build recoverable while replacing only this project's app.
if [[ -d "$FINAL_BUNDLE" ]]; then
  PREVIOUS_BUNDLE="$BUILD_DIR/Previous-$(date +%Y%m%d-%H%M%S).app"
  mv "$FINAL_BUNDLE" "$PREVIOUS_BUNDLE"
fi
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$FINAL_BUNDLE"
/usr/bin/xattr -cr "$FINAL_BUNDLE"
# The signed staging app has already passed strict verification. iCloud Desktop
# can immediately add its own FinderInfo to the loose copy, which codesign's
# strict checker rejects despite unchanged executable/resources. Keep a clean
# distribution archive from the verified staging bundle as well.
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/常在待办-Mac.zip"
print -r -- "已生成：$FINAL_BUNDLE"
