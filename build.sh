#!/bin/bash
# Builds Passage.app. Needs only the Xcode Command Line Tools.
#   ./build.sh            build into build/
#   ./build.sh --install  build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
ARCH="$(uname -m)"
APP="build/Passage.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
  -target "$ARCH-apple-macos14.0" \
  -o "$APP/Contents/MacOS/Passage" App/*.swift

cp Helper/passage-helper Helper/install-helper.sh Helper/uninstall-helper.sh "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/"*
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Passage</string>
  <key>CFBundleDisplayName</key><string>Passage</string>
  <key>CFBundleIdentifier</key><string>io.github.neomis.passage</string>
  <key>CFBundleExecutable</key><string>Passage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"
echo "Built $APP ($VERSION, $ARCH)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Passage 2>/dev/null || true
  rm -rf /Applications/Passage.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Passage.app"
fi
