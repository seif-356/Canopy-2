#!/bin/bash
# Launches Canopy 2 in each smoke-test scene on a real Mac (the CI runner),
# screenshots it, and collects logs and crash reports into OUT.
# Usage: ci/smoke-test.sh path/to/Canopy2.app [OUT]
set -uo pipefail

APP="${1:?Usage: $0 path/to/Canopy2.app [OUT]}"
OUT="${2:-smoke}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$APP/Contents/MacOS/Canopy2"
mkdir -p "$OUT"
: > "$OUT/errors.txt"

sw_vers > "$OUT/system.txt"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Display Type|Main Display" >> "$OUT/system.txt" || true

ls -la "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" > "$OUT/bundle.txt" 2>&1
defaults write com.seif356.Canopy2 weatherCity "Cupertino"

echo "Building the fake player"
swiftc -O -o "$OUT/fake-player" "$ROOT/ci/FakePlayer.swift" 2>&1 | tail -5
"$OUT/fake-player" 900 "Blinding Lights" "The Weeknd" "After Hours" 200 > "$OUT/fake-player.log" 2>&1 &
FAKE=$!
sleep 3

# What the MediaRemote adapter sees (should be the fake song).
/usr/bin/perl "$APP/Contents/Resources/mediaremote-adapter.pl" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" get --no-artwork > "$OUT/adapter-get.json" 2>&1 || true

shoot() {
  local scene="$1" wait="$2"
  shift 2
  echo "Scene: $scene"
  # No Downloads watching in CI (it would raise a permission prompt); the airdrop
  # scene plays the animation directly.
  "$BIN" -smokeScene "$scene" -airDropShelf NO "$@" > "$OUT/$scene.log" 2>&1 &
  local pid=$!
  sleep "$wait"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "$scene: app exited early" >> "$OUT/errors.txt"
  fi
  screencapture -x "$OUT/$scene.png" 2>> "$OUT/errors.txt" || echo "$scene: screencapture failed" >> "$OUT/errors.txt"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1
}

shoot notch-open 8
shoot notch-closed 9
shoot lyrics 10
shoot shelf 6
shoot hud 5
shoot status 5
shoot banner 5
shoot settings 6
shoot lockscreen 9
shoot lockscreen-constellation 9 -lockScreenLyricsStyle constellation
shoot desktop 10 -desktopSkin YES
# Night Mode, without the system audio tap (it would ask for permission).
# Restart the song in the chorus so the shots land on lyrics, not the outro.
kill "$FAKE" 2>/dev/null
"$OUT/fake-player" 600 "Blinding Lights" "The Weeknd" "After Hours" 200 62 >> "$OUT/fake-player.log" 2>&1 &
FAKE=$!
sleep 3
shoot night-words 9 -nightLyricsStyle words -reactToMusic NO
shoot night-constellation 9 -nightLyricsStyle constellation -reactToMusic NO
shoot night-wave 9 -nightLyricsStyle wave -reactToMusic NO
shoot airdrop 8

kill "$FAKE" 2>/dev/null

# Small JPEG copies in the log too, so they can be read where artifact
# downloads aren't reachable. Between SMOKE-IMAGE-BEGIN/END markers, base64.
for png in "$OUT"/*.png; do
  name="$(basename "$png" .png)"
  sips -s format jpeg -s formatOptions 55 -Z 900 "$png" --out "$OUT/$name.jpg" > /dev/null 2>&1 || continue
  echo "SMOKE-IMAGE-BEGIN $name"
  base64 -i "$OUT/$name.jpg" | fold -w 900
  echo "SMOKE-IMAGE-END $name"
  rm -f "$OUT/$name.jpg"
done

cp ~/Library/Logs/DiagnosticReports/Canopy2* "$OUT/" 2>/dev/null || true
ls -la "$OUT"
echo "--- errors ---"
cat "$OUT/errors.txt"
