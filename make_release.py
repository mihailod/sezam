#!/usr/bin/env python3
"""
Turn build/sezam.db into the two files published on archive.org.

    sezam.db.gz            the compressed database the app downloads
    sezam-manifest.json    sha256, sizes and row counts; the app fetches this
                           first so it knows what a complete install looks like

The database URL is a placeholder until the archive.org item exists. Set it with
    SEZAM_DB_URL=https://archive.org/download/<item>/sezam.db.gz python3 make_release.py
"""
import gzip, hashlib, json, os, shutil, sqlite3, sys, time

ROOT = os.path.dirname(os.path.abspath(__file__))
DB   = os.path.join(ROOT, "build", "sezam.db")
GZ   = DB + ".gz"
MAN  = os.path.join(ROOT, "build", "sezam-manifest.json")
URL  = os.environ.get("SEZAM_DB_URL", "REPLACE_WITH_ARCHIVE_ORG_URL/sezam.db.gz")

def main():
    t0 = time.time()
    db = sqlite3.connect(DB)
    print("integrity_check:", db.execute("PRAGMA quick_check").fetchone()[0], flush=True)
    counts = {t: db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
              for t in ("message", "user", "author", "topic", "conference")}
    db.execute("VACUUM"); db.close()
    raw = os.path.getsize(DB)
    print("counts:", counts, flush=True)
    print(f"database: {raw/1e6:.0f} MB (after VACUUM)", flush=True)

    # gzip, not zstd or lzma: iOS decodes it natively via the Compression
    # framework (raw DEFLATE plus a hand-parsed gzip header) and it streams, so
    # the phone never holds more than a small buffer in memory.
    #
    # mtime=0 and no embedded filename: gzip otherwise stamps the current time
    # into its header, so two runs over identical input produce byte-different
    # files with different checksums. That silently invalidates a manifest
    # against an already-published .gz — the app would download the right file
    # and reject it on the hash.
    #
    # And the .gz is not rebuilt if it is already newer than the database, so
    # re-running only to correct a URL cannot orphan a published upload.
    if os.path.exists(GZ) and os.path.getmtime(GZ) >= os.path.getmtime(DB) \
       and os.environ.get("SEZAM_FORCE_GZ") != "1":
        print("reusing existing sezam.db.gz (set SEZAM_FORCE_GZ=1 to rebuild)", flush=True)
    else:
        print("compressing…", flush=True)
        with open(DB, "rb") as f:
            with open(GZ, "wb") as raw:
                with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9,
                                   filename="", mtime=0) as g:
                    shutil.copyfileobj(f, g, length=8 * 1024 * 1024)
    gz = os.path.getsize(GZ)

    h = hashlib.sha256()
    with open(GZ, "rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)

    manifest = {
        "schema_version": 1,
        "database_url": URL,
        "compressed_size": gz,
        "compressed_sha256": h.hexdigest(),
        "uncompressed_size": raw,
        "message_count": counts["message"],
        "user_count": counts["user"],
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    json.dump(manifest, open(MAN, "w"), indent=2)

    print(f"\n  {GZ}\n    {gz:,} bytes ({gz/1e6:.0f} MB, {raw/gz:.1f}x smaller)")
    print(f"  {MAN}\n    sha256 {manifest['compressed_sha256']}")
    print(f"\nelapsed {time.time()-t0:.0f}s")
    if URL.startswith("REPLACE"):
        print("\nNOTE: database_url is a placeholder. After uploading, re-run with")
        print("  SEZAM_DB_URL=https://archive.org/download/<item>/sezam.db.gz python3 make_release.py")
        print("or edit build/sezam-manifest.json before uploading it.")

if __name__ == "__main__":
    main()
