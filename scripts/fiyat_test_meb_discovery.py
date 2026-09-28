import copy
import json
import sys
from pathlib import Path

PR = Path(__file__).resolve().parents[2] / "rotalink-data" / "price_research"
sys.path.insert(0, str(PR))
sys.stdout.reconfigure(encoding="utf-8")
import monitor  # noqa: E402
from common import Fetcher  # noqa: E402

root = PR.parent
master_doc = json.loads((root / "master_database_updated.json").read_text(encoding="utf-8"))
reg = {"tesisler": []}
f = Fetcher(per_host_delay=1.5)
kur = json.loads((PR / "kurumlar.json").read_text(encoding="utf-8"))
res = monitor.discover_meb(f, kur["ozel_kaynaklar"]["meb_ogretmenevi_listesi"], master_doc["tesisler"])
print("durum", res["durum"], "satir", res.get("liste_satiri"), "yeni", len(res["yeni"]))
for y in res["yeni"]:
    print("  ", y)
added, skipped = monitor.auto_add_facilities(f, res["yeni"], copy.deepcopy(master_doc), reg, 30, "test")
print("eklenecek", len(added))
for x in added:
    print("  +", x)
for x in skipped:
    print("  -", x["il"], x["ilce"], x["kurum"], "|", x["neden"])
