#!/usr/bin/env python3
"""DEPRECATED — Pexels/Wiki görsel çekimi kapatıldı.

Yerine:
  python scripts/fetch_google_places_to_bunny.py

Gerekli:
  scripts/.google_places_key
  scripts/.bunny_config.json   (örnek: .bunny_config.example.json)
"""

from __future__ import annotations

import sys

print(
    "DEPRECATED: Pexels fetch kapatıldı.\n"
    "Kullanın: python scripts/fetch_google_places_to_bunny.py",
    file=sys.stderr,
)
raise SystemExit(2)
