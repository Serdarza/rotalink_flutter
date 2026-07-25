import io
import time
import urllib.request

from PIL import Image

url = ("https://rotalink-media.b-cdn.net/konaklama/adana/"
       "adana-adana-orduevi.jpg")

for label, u in [
    ("normal", url),
    ("cache-bust", url + f"?v={int(time.time())}"),
]:
    req = urllib.request.Request(u, headers={"User-Agent": "RotalinkVerify/1.0"})
    with urllib.request.urlopen(req, timeout=40) as resp:
        body = resp.read()
    kind = "WEBP" if body[8:12] == b"WEBP" else ("JPEG" if body[:3] == b"\xff\xd8\xff" else "?")
    img = Image.open(io.BytesIO(body))
    print(f"{label:10} {len(body)//1024} KB  {kind}  {img.width}x{img.height}  "
          f"ct={resp.headers.get('Content-Type')}  cache={resp.headers.get('CDN-Cache')}")
