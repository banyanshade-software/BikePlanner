#!/bin/bash
# Builds BikePlanner-<version>.dmg (#37, universal app): the Finder window shows a background image with the version
# (drawn by packaging/dmg/make_background.swift), the app,
# a link to /Applications and an arrow inviting to drag the app onto it, and "Read Me.txt" / "Lisez-moi.txt"
# (packaging/dmg/, @VERSION@ replaced): how to open the app the first time (not notarized).
#
#   scripts/make_dmg.sh                 # Release build (ad hoc signed), DMG in build/
#   scripts/make_dmg.sh --app <path>    # package an already built app
#   scripts/make_dmg.sh --no-layout     # skip the Finder layout (no AppleScript, e.g. headless): plain window
#
# The Finder layout is set with AppleScript: the first run asks to allow Terminal to control Finder.
# The window geometry must match packaging/dmg/make_background.swift (660 x 480, 100 pt icons at (165,165) /
# (495,165), read-me files at (270,360) / (390,360)).
# The app embeds Secret.h (Thunderforest and Google Maps keys) and is not notarized: see doc/03-distribution-constraints.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP=""
LAYOUT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --no-layout) LAYOUT=0; shift ;;
        *) echo "usage: $0 [--app path/BikePlanner.app] [--no-layout]" >&2; exit 2 ;;
    esac
done

mkdir -p "$OUT"
if [ -z "$APP" ]; then
    echo "== Release build"
    xcodebuild -project "$ROOT/BikePlanner.xcodeproj" -scheme BikePlanner -configuration Release \
        -destination "generic/platform=macOS" -derivedDataPath "$OUT/DerivedData" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build -quiet
    APP="$OUT/DerivedData/Build/Products/Release/BikePlanner.app"
fi
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

# the API keys of Secret.h (Thunderforest, Google Maps #49) must not be in clear in the binaries (#51); keys are
# never printed
if [ -f "$ROOT/BikePlanner/Secret.h" ]; then
    if ! python3 - "$ROOT/BikePlanner/Secret.h" "$APP/Contents/MacOS" <<'PYEOF'
import re, sys, os
src = open(sys.argv[1]).read()
for name in ("THUNDERFOREST_API_KEY", "GOOGLE_MAPS_API_KEY"):
    m = re.search(r'#define\s+' + name + r'\s+"([^"]*)"', src)
    key = m.group(1).encode() if m else b""
    if len(key) < 8: continue   # example key, or no key
    for f in os.listdir(sys.argv[2]):
        if key in open(os.path.join(sys.argv[2], f), "rb").read():
            print(f"{name} in clear in {f}: not packaged (#51)", file=sys.stderr)
            sys.exit(1)
PYEOF
    then exit 1; fi
fi

INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO")
COMMIT=$(/usr/libexec/PlistBuddy -c "Print :BPGitCommit" "$INFO" 2>/dev/null || echo "?")
VOLNAME="BikePlanner $VERSION"
DMG="$OUT/BikePlanner-$VERSION.dmg"
echo "== Packaging $APP ($VERSION, build $BUILD, $COMMIT)"

# staging: app, link to /Applications, background (hidden folder)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/bp-dmg.XXXXXX")
RWDMG="$STAGE.rw.dmg"
MOUNT=""
cleanup() {
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
    rm -rf "$STAGE" "$STAGE.bg" "$RWDMG"
}
trap cleanup EXIT

ditto "$APP" "$STAGE/BikePlanner.app"
ln -s /Applications "$STAGE/Applications"
for f in "Read Me.txt" "Lisez-moi.txt"; do
    sed "s/@VERSION@/$VERSION/g" "$ROOT/packaging/dmg/$f" > "$STAGE/$f"
done
mkdir "$STAGE/.background" "$STAGE.bg"
# background with the version, 1x + 2x in one multi-resolution TIFF, so it is sharp on Retina screens
swift "$ROOT/packaging/dmg/make_background.swift" "$STAGE.bg" "$VERSION" >/dev/null
tiffutil -cathidpicheck "$STAGE.bg/background.png" "$STAGE.bg/background@2x.png" \
    -out "$STAGE/.background/background.tiff" 2>/dev/null

# read-write image, laid out by Finder, then compressed
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RWDMG"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RWDMG" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')
[ -d "$MOUNT" ] || { echo "could not mount $RWDMG" >&2; exit 1; }

if [ "$LAYOUT" = 1 ]; then
    echo "== Finder layout"
    DISK=$(basename "$MOUNT")
    osascript <<EOF
tell application "Finder"
    tell disk "$DISK"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 600}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 100
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "BikePlanner.app" of container window to {165, 165}
        set position of item "Applications" of container window to {495, 165}
        set position of item "Read Me.txt" of container window to {270, 360}
        set position of item "Lisez-moi.txt" of container window to {390, 360}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
    sync
    sleep 1
fi

# volume icon = app icon, set after the Finder layout (it is lost when set before)
ICNS="$APP/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$MOUNT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT" 2>/dev/null || true
fi
rm -rf "$MOUNT/.fseventsd"
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
hdiutil detach "$MOUNT" -quiet
MOUNT=""
rm -f "$DMG"
hdiutil convert -quiet "$RWDMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
# icon of the .dmg file itself = app icon (stored in the file's extended attributes: kept locally, usually lost
# when downloaded from the web)
if [ -f "$ICNS" ]; then
    osascript -l JavaScript - "$ICNS" "$DMG" >/dev/null <<'EOF'
ObjC.import('AppKit');
function run(argv) {
    const icon = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
    $.NSWorkspace.sharedWorkspace.setIconForFileOptions(icon, argv[1], 0);
}
EOF
fi
echo "== $DMG"
