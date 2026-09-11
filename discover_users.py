#!/usr/bin/env python3
"""
Find users who never posted a message (so are absent from the author list).

/Users is substring-matched and hard-capped at 20 rows with no pagination, so a
query returning exactly 20 is SATURATED -- there may be more behind it. Every
record whose fields are >= 2 chars contains at least one 2-gram, so sweeping all
2-grams and recursively refining only the saturated ones is exhaustive.

  --sample N   fetch N random 2-grams and report what fraction of users found
               are new (cheap: estimates whether a full sweep is worth hours)
  --sweep D    adaptive sweep, refining saturated queries up to length D
               (D=2 is the cheap first pass: every 2-gram, no refinement)
  --full       adaptive sweep with no depth limit (exhaustive, slow)

Shares harvest_users.py's cache and rate limiter, so nothing is fetched twice.
"""
import os, sys, random, sqlite3, importlib.util, time, collections

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("h", os.path.join(HERE, "harvest_users.py"))
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)

ALPHA = "abcdefghijklmnopqrstuvwxyz0123456789.-_ čćžšđ"
CAP   = 20

def known_usernames(db):
    return {r[0].lower() for r in db.execute("SELECT username FROM author")}

def store(db, rows, via):
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
    """, [dict(r, found_via=via, fetched_at=now,
               member_since_iso=h.iso_date(r["member_since"]),
               last_seen_iso=h.iso_date(r["last_seen"])) for r in rows])

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--sample"
    assert h.DB.endswith(".db"), f"module import clobbered DB path: {h.DB!r}"
    n_arg = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    os.makedirs(h.CACHE, exist_ok=True)
    db = sqlite3.connect(h.DB); db.executescript(h.SCHEMA); db.commit()
    known = known_usernames(db)
    have  = {r[0].lower() for r in db.execute("SELECT username FROM user")}
    print(f"authors known {len(known):,} | profiles already stored {len(have):,}", flush=True)

    grams = [a + b for a in ALPHA.strip() for b in ALPHA.strip()]
    if mode == "--sample":
        random.seed(7); picks = random.sample(grams, min(n_arg, len(grams)))
        seen, new_all, sat = {}, set(), 0
        for i, g in enumerate(picks, 1):
            rows = h.parse(h.fetch(g)[0])
            if len(rows) >= CAP: sat += 1
            for r in rows:
                k = r["username"].lower()
                seen.setdefault(k, r)
                if k not in known and k not in have: new_all.add(k)
            if i % 20 == 0: print(f"  {i}/{len(picks)} grams, {len(seen)} users, {len(new_all)} new", flush=True)
        if seen: store(db, list(seen.values()), "sample-2gram"); db.commit()
        print(f"\nsampled {len(picks)} 2-grams ({sat} saturated at {CAP})")
        print(f"distinct users seen : {len(seen):,}")
        print(f"NOT in author list  : {len(new_all):,}  ({len(new_all)/max(len(seen),1)*100:.1f}%)")
        if new_all:
            print("  examples:", ", ".join(sorted(new_all)[:12]))
        print(f"\nfull sweep would be ~{len(grams):,} 2-grams + refinement of saturated ones.")
    else:
        maxlen = 99 if mode == "--full" else (n_arg if mode == "--sweep" else 2)
        queue = collections.deque(grams); done_q = 0; found = {}; sat = 0
        while queue:
            g = queue.popleft(); done_q += 1
            rows = h.parse(h.fetch(g)[0])
            for r in rows: found.setdefault(r["username"].lower(), r)
            if len(rows) >= CAP:
                sat += 1
                if len(g) < maxlen:
                    for c in ALPHA:
                        queue.append(g + c)
            if done_q % 200 == 0:
                print(f"  {done_q:,} queries done, {len(queue):,} queued, {len(found):,} users", flush=True)
                store(db, list(found.values()), "sweep"); db.commit()
        store(db, list(found.values()), "sweep"); db.commit()
        print(f"\nsweep complete: {done_q:,} queries, {len(found):,} distinct users")
        print(f"saturated (>= {CAP} rows, may hide more): {sat:,}")
        if maxlen < 99 and sat:
            print(f"-> refining those to length {maxlen+1} would cost ~{sat*len(ALPHA):,} more queries")
    n = db.execute("SELECT count(*) FROM user").fetchone()[0]
    print(f"user table now: {n:,} rows")
    db.close()

if __name__ == "__main__":
    main()
