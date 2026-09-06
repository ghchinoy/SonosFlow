#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

BUILD_CONFIG="debug"
if [ "$1" == "--release" ] || [ "$1" == "-c release" ]; then
    BUILD_CONFIG="release"
fi

mkdir -p "$DIR/.cache/clang" "$DIR/.cache/tmp"
SWIFT_BUILD_FLAGS="--disable-sandbox -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc $DIR/.cache/clang -Xswiftc -module-cache-path -Xswiftc $DIR/.cache/clang"

if [ "$BUILD_CONFIG" == "release" ]; then
    echo "🔨 Building SonosFlow (release)..."
    swift build $SWIFT_BUILD_FLAGS -c release --product SonosFlow
    BIN_DIR="$DIR/.build/release"
else
    echo "⚡️ Building SonosFlow (debug)..."
    swift build $SWIFT_BUILD_FLAGS --product SonosFlow
    BIN_DIR="$DIR/.build/debug"
fi

APP_NAME="SonosFlow.app"
APP_DIR="$DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_DIR/SonosFlow" "$MACOS_DIR/SonosFlow"
chmod +x "$MACOS_DIR/SonosFlow"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SonosFlow</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.sonosflow.app</string>
    <key>CFBundleName</key>
    <string>SonosFlow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

touch "$APP_DIR"
echo "✅ Ready: $APP_NAME"
