#!/usr/bin/env python3
"""
Link harvested user profiles to message authors and make people searchable.

Three things happen here:
  1. author.user_id  -> the harvested profile row (case-insensitive username match)
  2. user_search     -> a people index (username / full name / city / company)
  3. `search` gets a `person` column carrying username + real name, so searching
     "Ristanovic" finds every message dejanr ever wrote. That was the whole point:
     the original site's user search never linked through to a person's messages.

Idempotent -- safe to re-run after another harvest pass.
"""
import sqlite3, sys, time, unicodedata as ud

DB = sys.argv[1] if len(sys.argv) > 1 else "/Users/mihailod/Documents/sezam/build/sezam.db"
FOLD = str.maketrans({"đ": "d", "Đ": "D", "Ł": "", "Ć": "C"})
fold = lambda s: ud.normalize("NFC", s or "").translate(FOLD)

db = sqlite3.connect(DB)
db.execute("PRAGMA journal_mode=OFF"); db.execute("PRAGMA synchronous=OFF")
t0 = time.time()

# 1 -- link -------------------------------------------------------------------
if "user_id" not in [r[1] for r in db.execute("PRAGMA table_info(author)")]:
    db.execute("ALTER TABLE author ADD COLUMN user_id INTEGER REFERENCES user(id)")
db.execute("""UPDATE author SET user_id=(
                SELECT u.id FROM user u WHERE lower(u.username)=lower(author.username))""")
db.execute("CREATE INDEX IF NOT EXISTS ix_author_user ON author(user_id)")
db.commit()

# 1b -- clamp last_seen to the archive era ------------------------------------
# The live site is a running telnet revival, so a handful of 1990s members have a
# present-day Last Seen. Sezam itself ended in 1999, so anything past the
# archive's high-water mark is clamped to it. The harvested value is never lost:
# it is kept in last_seen_observed and the row is flagged last_seen_clamped.
_cols = [r[1] for r in db.execute("PRAGMA table_info(user)")]
if "last_seen_observed" not in _cols:
    db.execute("ALTER TABLE user ADD COLUMN last_seen_observed TEXT")
    db.execute("ALTER TABLE user ADD COLUMN last_seen_clamped INTEGER DEFAULT 0")
_cap = db.execute("SELECT last_seen_iso, last_seen FROM user WHERE last_seen_iso < '2000' "
                  "ORDER BY last_seen_iso DESC LIMIT 1").fetchone()
if _cap:
    _n = db.execute("SELECT count(*) FROM user WHERE last_seen_iso >= '2000'").fetchone()[0]
    db.execute("""UPDATE user SET
                    last_seen_observed = COALESCE(last_seen_observed, last_seen),
                    last_seen = ?, last_seen_iso = ?, last_seen_clamped = 1
                  WHERE last_seen_iso >= '2000'""", (_cap[1], _cap[0]))
    db.commit()
    print(f"last_seen clamped to {_cap[1]} for {_n} row(s)")

# 2 -- people index -----------------------------------------------------------
db.create_function("fold", 1, fold, deterministic=True)
db.executescript("""
DROP TABLE IF EXISTS user_search;
CREATE VIRTUAL TABLE user_search USING fts5(
  username, full_name, city, company, content='',
  tokenize="unicode61 remove_diacritics 2");
""")
db.execute("""INSERT INTO user_search(rowid, username, full_name, city, company)
              SELECT id, fold(username), fold(full_name), fold(city), fold(company)
              FROM user""")
db.execute("INSERT INTO user_search(user_search) VALUES('optimize')")
db.commit()

# 3 -- rebuild message index with a person column -----------------------------
db.executescript("""
DROP TABLE IF EXISTS search;
CREATE VIRTUAL TABLE search USING fts5(
  body, author, topic, person, content='',
  tokenize="unicode61 remove_diacritics 2");
""")
db.execute("""
  INSERT INTO search(rowid, body, author, topic, person)
  SELECT m.id, fold(m.body), a.username, fold(t.name),
         fold(a.username || ' ' || COALESCE(u.full_name,'') || ' ' || COALESCE(u.city,''))
  FROM message m
  JOIN author a ON a.id = m.author_id
  JOIN topic  t ON t.id = m.topic_id
  LEFT JOIN user u ON u.id = a.user_id""")
db.execute("INSERT INTO search(search) VALUES('optimize')")
db.commit()

q = lambda s: db.execute(s).fetchone()[0]
print(f"users            : {q('SELECT count(*) FROM user'):,}")
print(f"authors linked   : {q('SELECT count(*) FROM author WHERE user_id IS NOT NULL'):,}"
      f" / {q('SELECT count(*) FROM author'):,}")
print(f"with full name   : {q('SELECT count(*) FROM user WHERE full_name IS NOT NULL'):,}")
print(f"with city        : {q('SELECT count(*) FROM user WHERE city IS NOT NULL'):,}")
print(f"with company     : {q('SELECT count(*) FROM user WHERE company IS NOT NULL'):,}")
print(f"rebuilt in {time.time()-t0:.0f}s")
db.execute("VACUUM"); db.close()
