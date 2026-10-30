#!/usr/bin/env bash
# Codemagic post-clone: GOOGLE_MAPS_API_KEY ortam değişkenini iOS xcconfig'e yazar.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/ios/Flutter/GoogleMaps.xcconfig"
if [ -z "${GOOGLE_MAPS_API_KEY:-}" ]; then
  echo "GOOGLE_MAPS_API_KEY yok; TestFlight harita anahtarsız derlenir."
  exit 0
fi
printf 'GOOGLE_MAPS_API_KEY = %s\n' "$GOOGLE_MAPS_API_KEY" > "$out"
echo "iOS Maps SDK anahtarı xcconfig'e yazıldı."
