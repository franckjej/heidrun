#!/usr/bin/env bash
#
# Heidrun release train — bump → commit → push → archive → DMG → notarize →
# staple → GitHub Release, in one shot.
#
#   Tools/release.sh <version>          e.g.  Tools/release.sh 1.0.6
#
# Prerequisite: CHANGELOG.md must already contain a "## [<version>]" section
# (the human-written notes). This script bumps MARKETING_VERSION in
# project.yml, commits + pushes "Release <version>", builds the signed
# archive, packages + notarizes the DMG, and publishes a GitHub Release whose
# notes are taken from that CHANGELOG section.
#
# Needs on PATH / available: xcodegen, xcodebuild, gh (authenticated), the
# shared ../.venv with dmgbuild installed, the "Developer ID Application:
# Daubit & Francke GmbH" signing identity, and the "AC_PASSWORD" notarytool
# keychain profile.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $(basename "$0") <version>   (e.g. 1.0.6)" >&2
    exit 2
fi

SIGN_ID="Developer ID Application: Daubit & Francke GmbH (6QDCK94P7Y)"
NOTARY_PROFILE="AC_PASSWORD"
REPO="franckjej/heidrun"
DMGBUILD="../.venv/bin/dmgbuild"

cd "$(dirname "$0")/.."   # repo root (this script lives in Tools/)

# --- preflight ---------------------------------------------------------------
for tool in xcodegen xcodebuild gh; do
    command -v "$tool" >/dev/null || { echo "✗ missing required tool: $tool" >&2; exit 1; }
done
[[ -x "$DMGBUILD" ]] || { echo "✗ dmgbuild not found at $DMGBUILD (create ../.venv and pip install dmgbuild)" >&2; exit 1; }
grep -q "^## \[$VERSION\]" CHANGELOG.md || {
    echo "✗ CHANGELOG.md has no '## [$VERSION]' section — write the release notes first." >&2
    exit 1
}
if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "✗ release $VERSION already exists on GitHub — aborting." >&2
    exit 1
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo "▶ Releasing Heidrun $VERSION from branch $BRANCH"

# --- version bump + commit + push --------------------------------------------
/usr/bin/sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
git add project.yml CHANGELOG.md
git diff --cached --quiet || git commit -m "Release $VERSION"
git push origin "$BRANCH"

# --- archive (Release config, already Developer ID-signed via project.yml) ----
xcodegen generate
rm -rf build/Heidrun.xcarchive
xcodebuild -project Heidrun.xcodeproj -scheme Heidrun -configuration Release \
    -archivePath build/Heidrun.xcarchive archive

APP="build/Heidrun.xcarchive/Products/Applications/Heidrun.app"
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$SHORT" == "$VERSION" ]] || { echo "✗ archived version ($SHORT) != requested ($VERSION)" >&2; exit 1; }
# Capture codesign output into a variable (no pipe → no SIGPIPE/pipefail
# false-negative, no dependency on whichever `grep` is on PATH) and match
# the exact signing identity with a bash substring test. On mismatch,
# echo what codesign actually reported so the failure is self-diagnosing.
SIG_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$SIG_INFO" != *"$SIGN_ID"* ]]; then
    echo "✗ archived app is NOT signed by the GmbH Developer ID identity" >&2
    echo "  expected identity: $SIGN_ID" >&2
    echo "  codesign reported:" >&2
    printf '%s\n' "$SIG_INFO" | /usr/bin/grep -i "Authority=" >&2 || true
    exit 1
fi
DMG="Releases/Heidrun-${SHORT}-${BUILD}.dmg"

# --- DMG → codesign → notarize → staple --------------------------------------
mkdir -p Releases
rm -f "$DMG"
"$DMGBUILD" -s dmg_settings.py -D app="$APP" Heidrun "$DMG"
codesign --sign "$SIGN_ID" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -vvv -t install "$DMG"

# --- GitHub release (notes pulled from the matching CHANGELOG section) --------
NOTES="$(/usr/bin/awk -v v="## [$VERSION]" '
    index($0, v)==1 { grab=1; next }   # start at this version header
    /^## \[/        { grab=0 }          # stop at the next version header
    grab            { print }
' CHANGELOG.md)"
gh release create "$VERSION" --repo "$REPO" --title "Heidrun $VERSION" \
    --notes "$NOTES" "$DMG"

echo "✅ Heidrun $VERSION (build $BUILD) released → https://github.com/$REPO/releases/tag/$VERSION"
