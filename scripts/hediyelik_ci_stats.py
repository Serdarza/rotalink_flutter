import collections
import json
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
rows = json.loads((pathlib.Path(__file__).parent / "out" / "ci_all.json").read_text(encoding="utf-8"))
print("toplam", len(rows))
print(collections.Counter(r["StatusName"] for r in rows))
print(collections.Counter(r["TypeName"].strip() for r in rows))
reg = [r for r in rows if r["StatusName"] == "Tescilli"]
print("tescil", len(reg))
print(collections.Counter(r["ProductGroupName"] for r in reg).most_common(40))
cities = collections.Counter(r["CityName"] for r in reg)
print(len(cities), sorted(cities.items(), key=lambda x: x[1])[:15])
for il in ["Düzce", "Kocaeli", "Bayburt", "Ardahan", "Tunceli", "Kilis"]:
    print(il, [r["Name"] for r in reg if r["CityName"] == il])
