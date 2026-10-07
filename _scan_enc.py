import pathlib
import re

ROOT = pathlib.Path(__file__).parent
SKIP = {".git", "build", ".dart_tool", "Pods", ".gradle", "node_modules", ".idea"}
TEXT = {".dart", ".arb", ".xml", ".json", ".yaml", ".yml", ".kt", ".swift", ".plist", ".strings", ".gradle", ".kts",
        ".html", ".js", ".txt", ".md", ".properties"}
BAD = re.compile("Ã[\u0080-\u00ff]|Ä[\u0080-\u00ff]|Å[\u0080-\u00ff]|\ufffd|â€")
for p in ROOT.rglob("*"):
    if any(part in SKIP for part in p.parts) or not p.is_file() or p.suffix not in TEXT or p.name == "_scan_enc.py":
        continue
    raw = p.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        print("UTF-16:", p.relative_to(ROOT))
        continue
    try:
        t = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        print("UTF-8 DEGIL:", p.relative_to(ROOT), e)
        continue
    if raw.startswith(b"\xef\xbb\xbf"):
        print("BOM:", p.relative_to(ROOT))
    hits = BAD.findall(t)
    if hits:
        print("BOZUK:", p.relative_to(ROOT), len(hits), sorted(set(hits))[:6])
print("tarama bitti")
