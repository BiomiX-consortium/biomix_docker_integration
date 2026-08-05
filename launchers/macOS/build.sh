#!/bin/bash
# Builds "BioMix Launcher.app" from the Swift sources in ./Sources.
# Requires only the Xcode Command Line Tools:  xcode-select --install
set -euo pipefail

APP_NAME="BioMix Launcher"
EXECUTABLE="BioMixLauncher"
BUNDLE_ID="org.biomix.launcher"
VERSION="1.0.0"
MIN_MACOS="13.0"

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
CONTENTS="$APP/Contents"

command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install"; exit 1; }

rm -rf "$BUILD"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
SOURCES=("$ROOT"/Sources/*.swift)

echo "==> Compiling"
SLICES=()
for ARCH in arm64 x86_64; do
  if swiftc -O -sdk "$SDK" -target "${ARCH}-apple-macos${MIN_MACOS}" \
       -parse-as-library -o "$BUILD/$EXECUTABLE-$ARCH" "${SOURCES[@]}" 2>"$BUILD/$ARCH.log"; then
    SLICES+=("$BUILD/$EXECUTABLE-$ARCH")
    echo "    $ARCH ok"
  else
    echo "    $ARCH skipped:"
    sed 's/^/      /' "$BUILD/$ARCH.log" | tail -n 20
  fi
done

if [ ${#SLICES[@]} -eq 0 ]; then
  echo "Compilation failed for every architecture."
  exit 1
fi

lipo -create -output "$CONTENTS/MacOS/$EXECUTABLE" "${SLICES[@]}"
chmod +x "$CONTENTS/MacOS/$EXECUTABLE"

echo "==> Copying resources"
shopt -s nullglob
for FILE in "$ROOT"/Resources/*; do
  cp -R "$FILE" "$CONTENTS/Resources/"
done
shopt -u nullglob

# Build an .icns from Resources/logo.png if one is supplied (1024x1024 works best).
ICON_LINE=""
if [ -f "$ROOT/Resources/logo.png" ]; then
  echo "==> Generating app icon"
  ICONSET="$BUILD/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for SIZE in 16 32 64 128 256 512; do
    sips -z $SIZE $SIZE "$ROOT/Resources/logo.png" \
      --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z $((SIZE * 2)) $((SIZE * 2)) "$ROOT/Resources/logo.png" \
      --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
  ICON_LINE="  <key>CFBundleIconFile</key><string>AppIcon</string>"
fi

echo "==> Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>BioMix Launcher opens a terminal window to run the analysis container.</string>
$ICON_LINE
</dict>
</plist>
PLIST

echo "==> Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  || echo "    ad-hoc signing skipped"

echo
echo "Built: $APP"
echo "Open it with:  open \"$APP\""
