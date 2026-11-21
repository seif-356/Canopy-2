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

# Listening for real: play a tone, pre-approve System Audio Recording when the
# runner allows it (SIP off), and check the app hears the sound through its tap.
# Last, because without approval macOS shows a permission prompt.
echo "--- audio check ---"
csrutil status 2>&1 | head -1
system_profiler SPAudioDataType 2>/dev/null | grep -E "^ {8}[^ ].*:$|Default Output Device|Output Channels" | head -12
NOW="$(date +%s)"
for db in "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "/Library/Application Support/com.apple.TCC/TCC.db"; do
  if sudo sqlite3 "$db" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags, last_modified) VALUES ('kTCCServiceAudioCapture', 'com.seif356.Canopy2', 0, 2, 3, 1, 0, $NOW);" 2>> "$OUT/tcc.log"; then
    echo "pre-approved in $db"
  fi
done
cat "$OUT/tcc.log" 2>/dev/null | head -4
python3 - "$OUT/tone.wav" <<'PY'
import math, struct, sys, wave
rate = 44100
notes = [110, 220, 165, 330, 247, 440, 196, 392]
out = wave.open(sys.argv[1], "wb")
out.setnchannels(1)
out.setsampwidth(2)
out.setframerate(rate)
frames = bytearray()
for i in range(rate * 30):
    t = i / rate
    f = notes[int(t * 2) % len(notes)]
    beat = 0.5 + 0.5 * math.cos(2 * math.pi * 2 * t)
    s = 0.4 * beat * math.sin(2 * math.pi * f * t) + 0.12 * math.sin(2 * math.pi * 3 * f * t)
    frames += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
out.writeframes(bytes(frames))
PY
afplay "$OUT/tone.wav" > "$OUT/afplay.log" 2>&1 &
PLAY=$!
shoot night-live 12 -nightLyricsStyle wave -reactToMusic YES
kill "$PLAY" 2>/dev/null
echo "afplay: $(cat "$OUT/afplay.log" 2>/dev/null | head -2)"
grep -h "Canopy2 audio" "$OUT/night-live.log" || echo "night-live: no audio log lines"

kill "$FAKE" 2>/dev/null

echo "--- app log summary ---"
grep -h -E "Canopy2 (media: using|lyrics|audio)" "$OUT"/*.log | sed -E 's/^.*(Canopy2 )/\1/' | sort | uniq -c

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
