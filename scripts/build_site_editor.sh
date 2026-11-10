#!/bin/bash
# Builds the app with the start sites editor (#67): a developer tool to edit BikePlanner/RemarkableSites.plist
# (menu Develop ▸ Start Sites Editor…). It is compiled only with BP_SITE_EDITOR=1, never in the normal builds nor
# in the DMG (scripts/make_dmg.sh refuses an app that contains it). Separate derived data (build/SiteEditor), so
# the normal Debug build is not affected.
#
#   scripts/build_site_editor.sh          # Debug build, prints the command to open it
#   scripts/build_site_editor.sh test     # unit tests with the editor (BPSiteEditorTests and the others)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/SiteEditor"
ACTION="${1:-build}"
case "$ACTION" in
    build|test) ;;
    *) echo "usage: $0 [build|test]" >&2; exit 2 ;;
esac

ARGS=(-project "$ROOT/BikePlanner.xcodeproj" -scheme BikePlanner -configuration Debug
      -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED"
      CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
      'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) BP_SITE_EDITOR=1')
if [ "$ACTION" = test ]; then
    xcodebuild "${ARGS[@]}" -only-testing:BikePlannerTests test 2>&1 \
        | grep -E "error:|Test case .*(failed|expected)|\*\* TEST"
else
    xcodebuild "${ARGS[@]}" build -quiet
    echo "open \"$DERIVED/Build/Products/Debug/BikePlanner.app\""
fi
