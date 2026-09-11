#!/usr/bin/env python3
"""
Harvest user directory rows from the live oldsezam.net into build/sezam.db.

The /Users endpoint is substring-matched, caps at 20 rows, has NO pagination and
no per-user detail page -- so the only exhaustive method is one exact-username
query per user. Usernames come from the 3,901 distinct <author> values already
extracted from the message archive.

Every response is cached to disk, so re-running is free and the job is resumable
after any interruption. Rows are never overwritten with less data: an upsert only
fills fields, and everything found is kept (including bonus rows that a substring
match happens to return).
"""
import os, re, sys, html, time, json, sqlite3, random, threading, urllib.parse
import urllib.request, unicodedata as ud
from concurrent.futures import ThreadPoolExecutor

# NOTE: read argv only under __main__ -- discover_users.py imports this module,
# and module-level sys.argv parsing would otherwise swallow the *importer's*
# arguments (a stray "--sample" once became the database path).
_HERE = os.path.dirname(os.path.abspath(__file__))
DB    = os.environ.get("SEZAM_DB",    os.path.join(_HERE, "build", "sezam.db"))
CACHE = os.environ.get("SEZAM_CACHE", os.path.join(_HERE, "build", "users_cache"))
BASE  = "https://oldsezam.net/Users"
UA    = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) sezam-archive-research/1.0"
WORKERS, RATE = 2, 2.5          # global requests/second ceiling

ROW = re.compile(r"<tr>\s*(?:<td>\s*(.*?)\s*</td>\s*){6}</tr>", re.S)
TD  = re.compile(r"<td>\s*(.*?)\s*</td>", re.S)
TBODY = re.compile(r"<tbody>(.*?)</tbody>", re.S)
MON = {m: i for i, m in enumerate(
    "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}
N = lambda s: ud.normalize("NFC", s)

def iso_date(s):
    """'25 Oct 89' or '22 Dec 99 02:40' -> ISO. 2-digit year: >=80 is 19xx."""
    m = re.match(r"^(\d{1,2}) (\w{3}) (\d{2})(?: (\d{2}):(\d{2}))?$", (s or "").strip())
    if not m: return None
    d, mon, y, h, mi = m.groups()
    if mon not in MON: return None
    y = int(y); y += 1900 if y >= 80 else 2000
    out = f"{y:04d}-{MON[mon]:02d}-{int(d):02d}"
    return out + (f"T{h}:{mi}" if h else "")

_lock, _last = threading.Lock(), [0.0]
def throttle():
    with _lock:
        gap = 1.0 / RATE
        wait = _last[0] + gap - time.monotonic()
        if wait > 0: time.sleep(wait)
        _last[0] = time.monotonic()

def cache_path(q):
    safe = urllib.parse.quote(q, safe="") or "_EMPTY_"
    return os.path.join(CACHE, safe[:180] + ".html")

def fetch(q, tries=4):
    p = cache_path(q)
    if os.path.exists(p) and os.path.getsize(p) > 0:
        return open(p, encoding="utf-8", errors="replace").read(), True
    url = BASE + "?q=" + urllib.parse.quote(q, safe="")
    for a in range(tries):
        throttle()
        try:
            rq = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(rq, timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            open(p, "w", encoding="utf-8").write(body)
            return body, False
        except Exception as e:
            if a == tries - 1:
                print(f"  FAIL q={q!r}: {e}", flush=True); return None, False
            time.sleep((2 ** a) + random.random())

def parse(src):
    tb = TBODY.search(src or "")
    if not tb: return []
    out = []
    for tr in re.findall(r"<tr>(.*?)</tr>", tb.group(1), re.S):
        tds = [N(html.unescape(x)).strip() for x in TD.findall(tr)]
        if len(tds) != 6 or not tds[0]: continue
        out.append(dict(username=tds[0], full_name=tds[1] or None, city=tds[2] or None,
                        company=tds[3] or None, member_since=tds[4] or None,
                        last_seen=tds[5] or None))
    return out

SCHEMA = """
CREATE TABLE IF NOT EXISTS user(
  id INTEGER PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  full_name TEXT, city TEXT, company TEXT,
  member_since TEXT, member_since_iso TEXT,
  last_seen TEXT,  last_seen_iso TEXT,
  found_via TEXT, fetched_at TEXT);
CREATE INDEX IF NOT EXISTS ix_user_city ON user(city);
CREATE INDEX IF NOT EXISTS ix_user_name ON user(full_name);
"""

def main():
    os.makedirs(CACHE, exist_ok=True)
    db = sqlite3.connect(DB); db.executescript(SCHEMA); db.commit()
    names = [r[0] for r in db.execute("SELECT username FROM author ORDER BY msg_count DESC")]
    print(f"{len(names):,} usernames to look up | cache {CACHE}", flush=True)

    seen, t0, done, hits, cached = {}, time.time(), [0], [0], [0]
    lk = threading.Lock()
    def work(u):
        src, was_cached = fetch(u)
        rows = parse(src)
        with lk:
            done[0] += 1
            if was_cached: cached[0] += 1
            for r in rows:
                k = r["username"].lower()
                if k not in seen:
                    r["found_via"] = u; seen[k] = r; hits[0] += 1
            if done[0] % 250 == 0:
                el = time.time() - t0
                print(f"  {done[0]:5,}/{len(names):,}  users={hits[0]:5,}  "
                      f"cached={cached[0]:5,}  {el:5.0f}s  eta {el/done[0]*(len(names)-done[0])/60:4.1f}m",
                      flush=True)
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        list(ex.map(work, names))

    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    db.executemany("""
      INSERT INTO user(username,full_name,city,company,member_since,member_since_iso,
                       last_seen,last_seen_iso,found_via,fetched_at)
      VALUES(:username,:full_name,:city,:company,:member_since,:member_since_iso,
             :last_seen,:last_seen_iso,:found_via,:fetched_at)
      ON CONFLICT(username) DO UPDATE SET
        full_name=COALESCE(excluded.full_name, user.full_name),
        city     =COALESCE(excluded.city,      user.city),
        company  =COALESCE(excluded.company,   user.company),
        member_since=COALESCE(excluded.member_since, user.member_since),
        member_since_iso=COALESCE(excluded.member_since_iso, user.member_since_iso),
        last_seen=COALESCE(excluded.last_seen, user.last_seen),
        last_seen_iso=COALESCE(excluded.last_seen_iso, user.last_seen_iso)
    """, [dict(r, fetched_at=now,
               member_since_iso=iso_date(r["member_since"]),
               last_seen_iso=iso_date(r["last_seen"])) for r in seen.values()])
    db.commit()
    n = db.execute("SELECT count(*) FROM user").fetchone()[0]
    matched = db.execute("""SELECT count(*) FROM author a
                            JOIN user u ON lower(u.username)=lower(a.username)""").fetchone()[0]
    print(f"\nusers stored      : {n:,}")
    print(f"authors matched   : {matched:,} / {len(names):,}")
    print(f"elapsed           : {(time.time()-t0)/60:.1f} min")
    db.close()

if __name__ == "__main__":
    if len(sys.argv) > 1: DB = sys.argv[1]
    if len(sys.argv) > 2: CACHE = sys.argv[2]
    main()
