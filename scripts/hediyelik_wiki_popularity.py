"""Tescilli ürün adlarının tr.wikipedia'da maddesi var mı → scripts/out/ci_wiki.json {Id: true}"""
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
OUT = pathlib.Path(__file__).parent / "out"
rows = [r for r in json.loads((OUT / "ci_all.json").read_text(encoding="utf-8")) if r["StatusName"] == "Tescilli"]


def variants(name):
    parts = [p.strip() for p in name.replace("\\", "/").split("/") if p.strip()]
    out = []
    for p in parts:
        t = " ".join(w[:1].upper() + w[1:].lower() for w in p.split())
        out.append(t)
        if len(t.split()) > 1:
            first, rest = t.split(" ", 1)
            out.append(first + " " + rest.lower())
    return list(dict.fromkeys(out))


title_to_ids = {}
for r in rows:
    for v in variants(r["Name"]):
        if len(v.split()) < 2:
            continue
        title_to_ids.setdefault(v, set()).add(r["Id"])

titles = list(title_to_ids)
found = set()
for i in range(0, len(titles), 50):
    batch = titles[i : i + 50]
    q = urllib.parse.urlencode({"action": "query", "titles": "|".join(batch), "redirects": 1, "format": "json"})
    req = urllib.request.Request(
        "https://tr.wikipedia.org/w/api.php?" + q,
        headers={"User-Agent": "RotalinkBot/1.0 (https://rotalink.tr; iletisim@rotalink.tr)"},
    )
    for attempt in range(6):
        try:
            data = json.loads(urllib.request.urlopen(req, timeout=60).read().decode("utf-8"))["query"]
            break
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit("Vikipedi sınırı aşılamadı")
    norm = {n["from"]: n["to"] for n in data.get("normalized", [])}
    redir = {n["from"]: n["to"] for n in data.get("redirects", [])}
    existing = {p["title"] for p in data.get("pages", {}).values() if "missing" not in p}
    for t in batch:
        final = redir.get(norm.get(t, t), norm.get(t, t))
        if final in existing:
            found.add(t)
    time.sleep(1.5)

hits = {}
for t in found:
    for i in title_to_ids[t]:
        hits[str(i)] = True
(OUT / "ci_wiki.json").write_text(json.dumps(hits), encoding="utf-8")
print("başlık", len(titles), "bulunan", len(found), "ürün", len(hits))
print(sorted(found)[:60])
