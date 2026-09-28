import json
from pathlib import Path

base = Path(__file__).resolve().parents[1]
hosts = sorted(json.loads((base / "data_out/fiyat/pol_pages.json").read_text(encoding="utf-8")))
p = base.parent / "rotalink-data/price_research/kurumlar.json"
d = json.loads(p.read_text(encoding="utf-8"))
d["emniyet_siteleri"] = hosts
p.write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(len(hosts))
