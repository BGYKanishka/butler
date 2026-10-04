#!/bin/bash
# Clears stale Screen Recording / Microphone entries for Butler, including entries left behind
# by older ad-hoc-signed builds (they show a toggle that is ON but does nothing).
# Run this ONCE after switching to stable signing, with Butler quit.
set -u
BUNDLE_ID="${1:-com.bgykanishka.butler}"
OLD_IDS=("$BUNDLE_ID" "com.example.Butler")

pkill -x Butler 2>/dev/null || true
for id in "${OLD_IDS[@]}"; do
  tccutil reset ScreenCapture "$id" 2>/dev/null && echo "reset ScreenCapture  $id"
  tccutil reset Microphone    "$id" 2>/dev/null && echo "reset Microphone     $id"
done
echo "Done. Launch Butler, tap Request Access, enable it in System Settings, then tap Restart Butler."
