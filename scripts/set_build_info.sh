#!/bin/sh
# "Set build info" Run Script phase of the BikePlanner target (#34): writes into the *built* Info.plist
#   CFBundleVersion = number of commits, BPGitCommit = short hash (+ "-dirty"), BPGitBranch = branch name.
# No-op when git or the repository is not available (e.g. source archive).
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
cd "${SRCROOT}" || exit 0
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    echo "set_build_info: no git repository, build info not set"
    exit 0
fi
COUNT=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse --short HEAD)
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then COMMIT="${COMMIT}-dirty"; fi
BRANCH=$(git rev-parse --abbrev-ref HEAD)

PB=/usr/libexec/PlistBuddy
set_key() {
    "$PB" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$PB" -c "Add :$1 string $2" "$PLIST"
}
set_key CFBundleVersion "$COUNT"
set_key BPGitCommit "$COMMIT"
set_key BPGitBranch "$BRANCH"
echo "set_build_info: build $COUNT, $COMMIT, $BRANCH"
