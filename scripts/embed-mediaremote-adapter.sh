#!/bin/bash
# Builds mediaremote-adapter (github.com/ungive/mediaremote-adapter, BSD 3-Clause)
# at a pinned commit and embeds it in Canopy2.app, then re-signs the app (ad hoc).
# It lets Canopy 2 see what any app is playing (browsers, Podcasts, VLC...).
# Without it, Canopy 2 still works but only sees Music and Spotify (AppleScript).
#
# Usage: scripts/embed-mediaremote-adapter.sh path/to/Canopy2.app
set -euo pipefail

APP="${1:?Usage: $0 path/to/Canopy2.app}"
COMMIT="0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/mediaremote-adapter"

if [ ! -d "$WORK/.git" ]; then
  rm -rf "$WORK"
  git init -q "$WORK"
  git -C "$WORK" remote add origin https://github.com/ungive/mediaremote-adapter.git
fi
git -C "$WORK" fetch -q --depth 1 origin "$COMMIT"
git -C "$WORK" checkout -q --force FETCH_HEAD

cmake -S "$WORK" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build "$WORK/build" --config Release

FRAMEWORK="$WORK/build/MediaRemoteAdapter.framework"
CLIENT="$WORK/build/MediaRemoteAdapterTestClient"
test -d "$FRAMEWORK"
test -x "$CLIENT"

mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources" "$APP/Contents/MacOS"
rm -rf "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$CLIENT" "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
cp "$WORK/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
cp "$WORK/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"

# Sign inside-out: nested code first, then the app with its entitlements.
codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
codesign --force --sign - --options runtime --entitlements "$ROOT/Canopy2.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "Embedded mediaremote-adapter ${COMMIT:0:7} in $APP"
