import sqlite3, re, unicodedata, json, collections
ROOT="/Users/mihailod/Documents/sezam"
SCRATCH="/private/tmp/claude-502/-Users-mihailod-Documents-sezam/27b4db58-b28e-4cb0-9dd2-c576cebf3ebd/scratchpad"

def fold(s):
    s = s.replace("đ","d").replace("Đ","D")
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s).strip().lower()

src = open(f"{ROOT}/app/Sources/Users/UserAliases.swift", encoding="utf-8").read()
m = re.search(r"static let cities: \[\[String\]\] = \[(.*?)\n    \]", src, re.S)
body = m.group(1) if m else ""
clusters = []
for line in body.splitlines():
    line = line.strip()
    if not line.startswith("["):
        continue
    items = [i.replace('\\"', '"') for i in re.findall(r'"((?:[^"\\]|\\.)*)"', line)]
    if items:
        clusters.append(items)
keymap = {}
for r in clusters:
    keep = fold(r[0])
    for v in r[1:]:
        keymap[fold(v)] = keep
print("city clusters parsed:", len(clusters), "variants mapped:", len(keymap))

con = sqlite3.connect(f"{ROOT}/build/sezam.db")
counts = collections.Counter()
raw_by_key = collections.defaultdict(collections.Counter)
total = 0
for (city,) in con.execute("SELECT city FROM user"):
    total += 1
    t = (city or "").strip()
    if not re.search(r"[0-9A-Za-zÀ-ž]", t):
        key = ""
    else:
        f = fold(t)
        key = keymap.get(f, f)
    counts[key] += 1
    if key:
        raw_by_key[key][t] += 1
print("users:", total, "distinct keys:", len([k for k in counts if k]), "unspecified:", counts[""])
json.dump({k: {"n": v, "raw": raw_by_key[k].most_common(3)} for k, v in counts.items()},
          open(f"{SCRATCH}/city_counts.json", "w"), ensure_ascii=False, indent=0)
for k, v in counts.most_common():
    if k:
        print(f"{v}\t{k}")
