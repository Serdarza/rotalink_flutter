import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
root = Path(__file__).resolve().parents[2] / "rotalink-data"
t = json.loads((root / "master_database_updated.json").read_text(encoding="utf-8"))["tesisler"]
for w in ["Antalya", "Diyarbakır", "Kars", "Bingöl", "Erzincan", "Nişantaşı", "Mardin", "Sincan", "Viranşehir",
          "Şebinkarahisar"]:
    hits = [(x["il"], x["isim"], x.get("tip"), x.get("telefon")) for x in t if w.lower() in (x["isim"] + " " + x["il"]).lower()
            and ("retmen" in x["isim"].lower() or "aso" in x["isim"].lower())]
    print(w, hits[:4])
print(sorted({x["il"] for x in t if "mara" in x["il"].lower() or "afyon" in x["il"].lower()}))
