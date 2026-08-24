#!/bin/zsh
# Builds Nimbus.app (release, arm64) and packages a distributable zip.
#
#   scripts/build-app.sh [version]
#
# Output: dist/Nimbus.app and dist/Nimbus-<version>-arm64.zip
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0-alpha.1}"
APP_NAME="Nimbus"
BUNDLE_ID="com.matthewdresden.nimbus"
BUILD_DIR=".build/release"
APP="dist/$APP_NAME.app"

echo "==> building release binary"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release

echo "==> generating icon"
mkdir -p dist/Resources
python3 scripts/make_icon.py dist/Resources

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/Nimbus" "$APP/Contents/MacOS/$APP_NAME"
cp "dist/Resources/$APP_NAME.icns" "$APP/Contents/Resources/$APP_NAME.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>          <string>Nimbus</string>
  <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>              <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
  <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleIconFile</key>             <string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key>       <string>13.0</string>
  <key>LSUIElement</key>                  <true/>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>NSHumanReadableCopyright</key>     <string>MIT License - https://github.com/matthew-dresden/nimbus</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesigning"
codesign --force --deep --sign - "$APP"

echo "==> zipping"
rm -f "dist/$APP_NAME-$VERSION-arm64.zip"
cd dist && zip -qry "$APP_NAME-$VERSION-arm64.zip" "$APP_NAME.app" && cd ..

echo "==> building dmg"
rm -rf "dist/$APP_NAME-$VERSION-arm64.dmg" dist/dmg-staging
mkdir -p dist/dmg-staging
cp -R "$APP" dist/dmg-staging/
ln -sf /Applications dist/dmg-staging/Applications
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder dist/dmg-staging \
  -ov -format UDZO \
  "dist/$APP_NAME-$VERSION-arm64.dmg" > /dev/null
rm -rf dist/dmg-staging

echo "==> done: dist/$APP_NAME-$VERSION-arm64.zip + dist/$APP_NAME-$VERSION-arm64.dmg"
