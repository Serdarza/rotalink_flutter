import urllib.request

BASE = "https://rotalink-media.b-cdn.net/konaklama/adana/adana-adana-jandarma-sosyal-tesisi.jpg"

TESTS = [
    ("orijinal", BASE, {}),
    ("width=800&q=80", BASE + "?width=800&quality=80", {}),
    ("width=400", BASE + "?width=400", {}),
    ("webp-accept", BASE, {"Accept": "image/webp,image/*"}),
    ("webp+width800", BASE + "?width=800&quality=80", {"Accept": "image/webp,image/*"}),
    ("avif-accept", BASE, {"Accept": "image/avif,image/*"}),
]

for name, url, extra in TESTS:
    headers = {"User-Agent": "RotalinkFlutter/1.0"}
    headers.update(extra)
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=40) as resp:
            body = resp.read()
            ctype = resp.headers.get("Content-Type")
            cache = resp.headers.get("CDN-Cache")
            print(f"{name:16} {len(body)//1024:5} KB  {ctype}  cache={cache}")
    except Exception as exc:
        print(f"{name:16} ERR {exc}")
