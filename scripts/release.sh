#!/usr/bin/env bash
#
# Build a signed, notarized, stapled Serenity DMG, publish it as a GitHub release and bump the
# Homebrew cask in vladikk/homebrew-tap.
#
# Prerequisites (one-time):
#   * "Developer ID Application" certificate in the login keychain.
#   * A notarytool keychain profile named by $NOTARY_PROFILE, created with:
#       xcrun notarytool store-credentials <name> \
#         --apple-id <you@example.com> --team-id ME75ER328P --password <app-specific>
#   * The sound loops in Sounds/ (python3 tools/build_sounds.py).
#
# Usage:
#   scripts/release.sh [version]        # version defaults to the VERSION file
#
# SKIP_RELEASE=1 builds the DMG without publishing; SKIP_CASK=1 leaves the tap untouched.
set -euo pipefail

TEAM_ID="ME75ER328P"
IDENTITY="Developer ID Application"
NOTARY_PROFILE="${NOTARY_PROFILE:-openmv7-notary}"
APP_NAME="Serenity"
TAP_REMOTE="https://github.com/vladikk/homebrew-tap.git"
CASK_NAME="serenity"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD="$ROOT/build"

VERSION="${1:-$(cat VERSION)}"
APP="$BUILD/$APP_NAME.app"
DMG_STAGING="$BUILD/dmg"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

echo "==> Releasing $APP_NAME $VERSION (team $TEAM_ID)"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY.*$TEAM_ID"; then
  echo "error: no '$IDENTITY ($TEAM_ID)' identity in keychain"; exit 1
fi
# Fail fast if the notary service won't accept submissions (e.g. an unsigned Apple agreement).
if ! NOTARY_CHECK="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
  echo "error: notary service rejected profile '$NOTARY_PROFILE':"; echo "$NOTARY_CHECK" | tail -3; exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree has uncommitted changes"; exit 1
fi

echo "==> Building app (universal, Developer ID, hardened runtime)"
VERSION="$VERSION" SIGN_IDENTITY="$IDENTITY: Vladislav Khononov ($TEAM_ID)" ./build.sh

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Building DMG"
rm -rf "$DMG_STAGING" "$DMG"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$DMG_STAGING"

echo "==> Signing DMG"
codesign --force --sign "$IDENTITY: Vladislav Khononov ($TEAM_ID)" --timestamp "$DMG"

echo "==> Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo "==> Publishing GitHub release v$VERSION"
if [ "${SKIP_RELEASE:-0}" = "1" ]; then
  echo "   SKIP_RELEASE=1 — upload manually: gh release create v$VERSION \"$DMG\" --generate-notes"
  exit 0
elif gh release view "v$VERSION" >/dev/null 2>&1; then
  gh release upload "v$VERSION" "$DMG" --clobber
  echo "   updated existing release v$VERSION"
else
  gh release create "v$VERSION" "$DMG" --title "$APP_NAME $VERSION" --generate-notes
  echo "   created release v$VERSION"
fi

echo "==> Updating Homebrew cask ($CASK_NAME $VERSION)"
if [ "${SKIP_CASK:-0}" = "1" ]; then
  echo "   SKIP_CASK=1 — tap untouched. version $VERSION  sha256 $SHA256"
else
  # The release above must exist first, or the cask URL 404s.
  TAP_DIR="$BUILD/homebrew-tap"
  rm -rf "$TAP_DIR"
  git clone -q --depth 1 "$TAP_REMOTE" "$TAP_DIR"
  CASK="$TAP_DIR/Casks/$CASK_NAME.rb"
  cp packaging/$CASK_NAME.rb "$CASK"
  sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
  sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" "$CASK"
  if [ -z "$(git -C "$TAP_DIR" status --porcelain)" ]; then
    echo "   cask already at $VERSION — nothing to push"
  else
    git -C "$TAP_DIR" add -A
    git -C "$TAP_DIR" commit -qm "$CASK_NAME $VERSION"
    git -C "$TAP_DIR" -c credential.helper= -c credential.helper="!gh auth git-credential" push -q
    echo "   pushed cask $VERSION to tap"
  fi
fi

echo ""
echo "Done: $DMG"
echo "   sha256: $SHA256"
echo "   install: brew install --cask vladikk/tap/$CASK_NAME"
