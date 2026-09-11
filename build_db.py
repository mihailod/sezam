#!/usr/bin/env python3
"""
Build a production, fully-indexed SQLite database from the oldsezam.net static mirror.

Source of truth is the mirror's semantic markup:
    <message><header><msgid>topic.N</msgid><author>x</author>
    <time title="dd/mm/yyyy HH:MM">..</time><reply>-> #M, y</reply></header>
    <content>..</content></message>

Repeatable: delete the output file and re-run.
"""
import os, re, html, sqlite3, sys, time, unicodedata as ud

MIRROR = sys.argv[1] if len(sys.argv) > 1 else "/Users/mihailod/Documents/sezam/oldsezam.net"
OUT    = sys.argv[2] if len(sys.argv) > 2 else "/Users/mihailod/Documents/sezam/build/sezam.db"
CONF   = os.path.join(MIRROR, "Conference")

# ---------- parsing ----------------------------------------------------------
# Two stage. Stage 1 is a single lazy match with a literal terminator (linear).
# Do NOT collapse these into one regex with several .*? groups -- that
# backtracks catastrophically on any page with a malformed message block.
CHUNK = re.compile(r"<message>(.*?)</message>", re.S)
F_ID  = re.compile(r"<msgid>([^<]*)</msgid>")
F_AU  = re.compile(r"<author>([^<]*)</author>")
F_TM  = re.compile(r'<time title="([^"]*)"')
F_RE  = re.compile(r"<reply>\s*->\s*#(\d+)\s*,\s*([^<]*?)\s*</reply>")
F_CO  = re.compile(r"<content>(.*?)</content>", re.S)
TOPIC_DECL = re.compile(
    r'<a href="[^"]+?\.html">([^<]*?) <span class="topic-sequence">\((\d+)\)</span></a>')
VOL_DATES  = re.compile(r"<p>(\d{1,2} \w{3} \d{4}) - (\d{1,2} \w{3} \d{4})</p>")
TS         = re.compile(r"^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})$")

N = lambda s: ud.normalize("NFC", s)          # macOS listdir yields NFD; DB is NFC

# Search-index folding. SQLite's `remove_diacritics 2` handles c-caron, s-caron,
# z-caron and c-acute, but NOT the stroke letters d-bar / D-bar (no Unicode
# decomposition), so `djubre`/`dubre` would miss. Fold them explicitly, and drop
# the two stray CP852 quote-prefix glyphs left over from the site's own encoding
# conversion. The stored body is never touched -- display stays verbatim.
FOLD = str.maketrans({"đ": "d", "Đ": "D", "Ł": "", "Ć": "C"})
def fold(s): return N(s).translate(FOLD)

def parse_ts(raw):
    """'19/11/1991 07:54' -> ('1991-11-19T07:54', epoch, ok)."""
    m = TS.match(raw or "")
    if not m: return None, None, False
    d, mo, y, h, mi = (int(x) for x in m.groups())
    if not (1989 <= y <= 2000 and 1 <= mo <= 12 and 1 <= d <= 31):
        return None, None, False
    iso = f"{y:04d}-{mo:02d}-{d:02d}T{h:02d}:{mi:02d}"
    import calendar
    try: epoch = calendar.timegm((y, mo, d, h, mi, 0, 0, 0, 0))
    except Exception: return None, None, False
    return iso, epoch, True

# ---------- schema -----------------------------------------------------------
SCHEMA = """
PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA cache_size=-400000;

CREATE TABLE conference(
  id INTEGER PRIMARY KEY, family TEXT NOT NULL, volume TEXT NOT NULL UNIQUE,
  ord INTEGER NOT NULL DEFAULT 0,     -- numeric volume no.; "FORUM.10" > "FORUM.2"
  date_from TEXT, date_to TEXT, msg_count INTEGER DEFAULT 0);

CREATE TABLE topic(
  id INTEGER PRIMARY KEY, conf_id INTEGER NOT NULL REFERENCES conference(id),
  name TEXT NOT NULL, declared_count INTEGER, msg_count INTEGER DEFAULT 0,
  first_ts TEXT, last_ts TEXT, UNIQUE(conf_id, name));

CREATE TABLE author(
  id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE,
  msg_count INTEGER DEFAULT 0, first_ts TEXT, last_ts TEXT);

CREATE TABLE message(
  id INTEGER PRIMARY KEY,
  topic_id INTEGER NOT NULL REFERENCES topic(id),
  seq INTEGER NOT NULL,
  author_id INTEGER NOT NULL REFERENCES author(id),
  ts TEXT, epoch INTEGER, ts_raw TEXT,
  reply_seq INTEGER, reply_author TEXT,
  year INTEGER,                       -- denormalised: substr(ts,1,4) cannot use an index
  body TEXT NOT NULL,
  UNIQUE(topic_id, seq));
"""

INDEXES = """
CREATE INDEX ix_msg_author  ON message(author_id, epoch);
-- A user's messages ordered by id: without this SQLite scans the whole
-- table by rowid (629 ms for the busiest author); with it, 0.11 ms.
CREATE INDEX ix_msg_author_id ON message(author_id, id);
CREATE INDEX ix_msg_topic   ON message(topic_id, seq);
CREATE INDEX ix_msg_epoch   ON message(epoch);
CREATE INDEX ix_msg_year    ON message(year);
CREATE INDEX ix_msg_reply   ON message(topic_id, reply_seq);
CREATE INDEX ix_topic_conf  ON topic(conf_id);
CREATE INDEX ix_conf_family ON conference(family, ord);
"""

def main():
    t0 = time.time()
    if os.path.exists(OUT): os.remove(OUT)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    db = sqlite3.connect(OUT)
    db.executescript(SCHEMA)

    # -- volume + declared-topic metadata from the conference index pages ------
    declared, voldates = {}, {}
    for fn in sorted(os.listdir(CONF)):
        if not fn.endswith(".html"): continue
        vol = N(fn[:-5])
        src = open(os.path.join(CONF, fn), encoding="utf-8", errors="replace").read()
        m = VOL_DATES.search(src)
        if m: voldates[vol] = m.groups()
        for tm in TOPIC_DECL.finditer(src):
            declared[(vol, N(html.unescape(tm.group(1)).strip()))] = int(tm.group(2))

    confs, topics, authors = {}, {}, {}
    def conf_id(vol):
        if vol not in confs:
            fam = vol.split(".")[0]
            df, dt = voldates.get(vol, (None, None))
            tail = vol.rpartition(".")[2]
            ordinal = int(tail) if tail.isdigit() else 0
            confs[vol] = db.execute(
                "INSERT INTO conference(family,volume,ord,date_from,date_to) VALUES(?,?,?,?,?)",
                (fam, vol, ordinal, df, dt)).lastrowid
        return confs[vol]
    def topic_id(vol, name):
        k = (vol, name)
        if k not in topics:
            topics[k] = db.execute(
                "INSERT INTO topic(conf_id,name,declared_count) VALUES(?,?,?)",
                (conf_id(vol), name, declared.get(k))).lastrowid
        return topics[k]
    def author_id(u):
        if u not in authors:
            authors[u] = db.execute(
                "INSERT INTO author(username) VALUES(?)", (u,)).lastrowid
        return authors[u]

    # -- messages -------------------------------------------------------------
    n_files = n_raw = n_bad = n_badts = 0
    seen, batch = set(), []
    INS = ("INSERT OR IGNORE INTO message"
           "(topic_id,seq,author_id,ts,epoch,ts_raw,reply_seq,reply_author,year,body)"
           " VALUES(?,?,?,?,?,?,?,?,?,?)")
    for vol_d in sorted(os.listdir(CONF)):
        d = os.path.join(CONF, vol_d)
        if not os.path.isdir(d): continue
        vol = N(vol_d)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".html"): continue
            n_files += 1
            src = open(os.path.join(d, fn), encoding="utf-8", errors="replace").read()
            for cm in CHUNK.finditer(src):
                ch = cm.group(1)
                mid, au, co = F_ID.search(ch), F_AU.search(ch), F_CO.search(ch)
                if not (mid and au and co): n_bad += 1; continue
                n_raw += 1
                msgid = N(html.unescape(mid.group(1)).strip())
                tname, _, seq = msgid.rpartition(".")
                try: seq = int(seq)
                except ValueError: tname, seq = msgid, 0
                key = (vol, tname, seq)
                if key in seen: continue          # page-1 triplication
                seen.add(key)
                tm = F_TM.search(ch)
                iso, epoch, ok = parse_ts(tm.group(1).strip() if tm else None)
                if not ok: n_badts += 1
                rp = F_RE.search(ch)
                batch.append((
                    topic_id(vol, tname), seq,
                    author_id(N(html.unescape(au.group(1)).strip())),
                    iso, epoch, tm.group(1).strip() if tm else None,
                    int(rp.group(1)) if rp else None,
                    N(html.unescape(rp.group(2))) if rp else None,
                    int(iso[:4]) if iso else None,
                    html.unescape(co.group(1))))
            if len(batch) >= 40000:
                db.executemany(INS, batch); batch = []
                print(f"  {n_files:5d} files  {len(seen):7,} msgs  {time.time()-t0:5.0f}s", flush=True)
    db.executemany(INS, batch); db.commit()
    print(f"parsed {n_files} files / {n_raw:,} blocks -> {len(seen):,} unique "
          f"({n_bad} unparsable, {n_badts} bad timestamps) in {time.time()-t0:.0f}s", flush=True)

    # -- indexes BEFORE rollups ----------------------------------------------
    # The rollups below are correlated subqueries grouped by topic_id/author_id.
    # Without these indexes each one full-scans message (1405 topics x 3 sub-
    # queries + 3901 authors x 3 subqueries over 572k rows ~= 9e9 row visits).
    # With them the whole rollup pass is seconds.
    db.execute("UPDATE message SET epoch=0 WHERE epoch IS NULL")
    db.executescript(INDEXES)
    db.executescript("""
      UPDATE topic SET
        msg_count=(SELECT count(*) FROM message m WHERE m.topic_id=topic.id),
        first_ts =(SELECT min(ts) FROM message m WHERE m.topic_id=topic.id),
        last_ts  =(SELECT max(ts) FROM message m WHERE m.topic_id=topic.id);
      UPDATE author SET
        msg_count=(SELECT count(*) FROM message m WHERE m.author_id=author.id),
        first_ts =(SELECT min(ts) FROM message m WHERE m.author_id=author.id),
        last_ts  =(SELECT max(ts) FROM message m WHERE m.author_id=author.id);
      UPDATE conference SET msg_count=(
        SELECT count(*) FROM message m JOIN topic t ON t.id=m.topic_id
        WHERE t.conf_id=conference.id);
    """)
    db.commit()
    print(f"indexes + rollups done ({time.time()-t0:.0f}s)", flush=True)

    # -- full-text index ------------------------------------------------------
    # content='' -> contentless: stores the inverted index only, no second copy
    # of the 400 MB of text. Display text is fetched from message.body by rowid.
    db.create_function("fold", 1, fold, deterministic=True)
    db.executescript("""
      CREATE VIRTUAL TABLE search USING fts5(
        body, author, topic, content='',
        tokenize="unicode61 remove_diacritics 2");
    """)
    db.execute("""
      INSERT INTO search(rowid, body, author, topic)
      SELECT m.id, fold(m.body), a.username, fold(t.name)
      FROM message m JOIN author a ON a.id=m.author_id
                     JOIN topic  t ON t.id=m.topic_id""")
    db.execute("INSERT INTO search(search) VALUES('optimize')")
    db.commit()
    print(f"FTS built ({time.time()-t0:.0f}s)", flush=True)

    db.execute("PRAGMA journal_mode=DELETE")
    ok = db.execute("PRAGMA integrity_check").fetchone()[0]
    fk = db.execute("PRAGMA foreign_key_check").fetchall()
    db.execute("VACUUM"); db.close()
    print(f"integrity_check={ok}  foreign_key_violations={len(fk)}")
    print(f"OUTPUT {OUT}  {os.path.getsize(OUT)/1e6:.0f} MB  total {time.time()-t0:.0f}s")

if __name__ == "__main__":
    main()
