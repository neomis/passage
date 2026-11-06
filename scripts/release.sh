#!/bin/bash
# Builds a release zip of Passage.app and prints its SHA-256 (for the Homebrew cask).
#   scripts/release.sh            uses the version in VERSION
#
# Release builds are ad-hoc signed: a local certificate means nothing on other Macs.
# They're Apple silicon only for now.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
ARCH="$(uname -m)"
ZIP="build/Passage-$VERSION-$ARCH.zip"

[[ -z "$(git status --porcelain)" ]] || { echo "error: commit your changes first" >&2; exit 1; }

PASSAGE_SIGN_IDENTITY=none ./build.sh
codesign --verify --deep --strict build/Passage.app

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/Passage.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo
echo "Release zip: $ZIP"
echo "SHA-256:     $SHA"
echo
echo "Next:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION $ZIP --title \"Passage $VERSION\" --notes-file <notes>"
echo "  Update version and sha256 in the homebrew-tap cask (Casks/passage.rb)"
