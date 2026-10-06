"""TÜRKPATENT coğrafi işaret veritabanını indirir → scripts/out/ci_all.json"""
import json
import pathlib
import sys
import urllib.parse
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
BASE = "https://ci.turkpatent.gov.tr"
HDR = {"User-Agent": "Mozilla/5.0", "X-Requested-With": "XMLHttpRequest"}


def post(path, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(BASE + path, data=body, headers=HDR)
    return json.loads(urllib.request.urlopen(req, timeout=120).read().decode("utf-8"))


def get(path):
    req = urllib.request.Request(BASE + path, headers=HDR)
    return json.loads(urllib.request.urlopen(req, timeout=60).read().decode("utf-8"))


out = pathlib.Path(__file__).parent / "out"
out.mkdir(exist_ok=True)
for name in ["CityList", "StatusList", "TypeList", "ProductGroupList"]:
    try:
        data = get(f"/Generals/{name}")
        (out / f"ci_{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        print(name, str(data)[:300])
    except Exception as e:
        print(name, "ERR", e)

rows = []
start = 0
while True:
    page = post("/Data/GetList", {"draw": 1, "start": start, "length": 500})
    data = page.get("data") or []
    rows.extend(data)
    total = page.get("recordsTotal") or page.get("recordsFiltered") or 0
    print("got", len(rows), "/", total)
    if not data or len(rows) >= total:
        break
    start += len(data)

(out / "ci_all.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
print(json.dumps(rows[:2], ensure_ascii=False, indent=1))
