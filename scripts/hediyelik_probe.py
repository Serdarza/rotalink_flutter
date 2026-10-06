import re
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

for u in sys.argv[1:]:
    try:
        req = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
        h = urllib.request.urlopen(req, timeout=40).read().decode("utf-8", "ignore")
        print("==", u, len(h))
        links = sorted(set(re.findall(r'href="([^"]+)"', h)))
        print("\n".join(links[:120]))
        print("--- text sample")
        text = re.sub(r"<script.*?</script>|<style.*?</style>", " ", h, flags=re.S)
        text = re.sub(r"<[^>]+>", " ", text)
        print(re.sub(r"\s+", " ", text)[:3000])
    except Exception as e:
        print("==", u, "ERR", e)
