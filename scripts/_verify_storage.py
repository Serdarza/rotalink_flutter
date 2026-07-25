import io
import json
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

cfg = json.loads((Path(__file__).parent / ".bunny_config.json").read_text(encoding="utf-8"))
zone = cfg["storage_zone"].strip()
endpoint = (cfg.get("storage_endpoint") or "storage.bunnycdn.com").strip() \
    .removeprefix("https://").removesuffix("/")

rel = "konaklama/adana/adana-adana-orduevi.jpg"
enc = "/".join(urllib.parse.quote(p, safe="") for p in rel.split("/"))
url = f"https://{endpoint}/{urllib.parse.quote(zone, safe='')}/{enc}"

req = urllib.request.Request(url, headers={"AccessKey": cfg["storage_password"].strip()})
with urllib.request.urlopen(req, timeout=40) as resp:
    body = resp.read()
kind = "WEBP" if body[8:12] == b"WEBP" else ("JPEG" if body[:3] == b"\xff\xd8\xff" else "?")
img = Image.open(io.BytesIO(body))
print(f"storage: {len(body)//1024} KB  {kind}  {img.width}x{img.height}")
