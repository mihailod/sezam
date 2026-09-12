#!/usr/bin/env python3
"""
Put the compressed archive inside the app, so the first launch is offline.

    python3 scripts/bundle_archive.py

Writes two files into app/Resources/, which the app target ships verbatim:

    sezam.db.gz            the archive, expanded on first launch
    sezam-manifest.json    what a complete install looks like: sizes, sha256,
                           row counts, and where to re-download from

This is NOT make_release.py. That one produces the pair published on
archive.org and must not be re-run casually: rewriting build/sezam-manifest.json
while the old .gz is still the one being served would make every downloading
app reject a file that is perfectly good. This script leaves the published
manifest alone and describes only the copy going into the bundle.

The two .gz files are not expected to be byte-identical -- gzip output varies
with the zlib build -- so the bundled manifest carries the bundled file's own
size and hash. `database_url` is copied from the published manifest, since a
re-download must still fetch the published copy.

The .gz is reused when it is newer than the database (compressing 773 MB at
level 9 takes about a minute). Set SEZAM_FORCE_GZ=1 to rebuild it anyway.
"""
import gzip, hashlib, json, os, shutil, sqlite3, sys, time

ROOT      = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB        = os.path.join(ROOT, "build", "sezam.db")
BUILD_GZ  = os.path.join(ROOT, "build", "sezam.db.gz")
PUBLISHED = os.path.join(ROOT, "build", "sezam-manifest.json")
RES       = os.path.join(ROOT, "app", "Resources")
RES_GZ    = os.path.join(RES, "sezam.db.gz")
RES_MAN   = os.path.join(RES, "sezam-manifest.json")


def compress():
    """Deterministic gzip: mtime=0 and no embedded filename, so re-running over
    unchanged input does not produce a file with a different checksum."""
    if os.path.exists(BUILD_GZ) and os.path.getmtime(BUILD_GZ) >= os.path.getmtime(DB) \
       and os.environ.get("SEZAM_FORCE_GZ") != "1":
        print("reusing build/sezam.db.gz (SEZAM_FORCE_GZ=1 to rebuild)", flush=True)
        return
    print("compressing… (about a minute)", flush=True)
    with open(DB, "rb") as f, open(BUILD_GZ, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9,
                           filename="", mtime=0) as g:
            shutil.copyfileobj(f, g, length=8 * 1024 * 1024)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if not os.path.exists(DB):
        sys.exit(f"no database at {DB} -- run scripts/rebuild_db.sh first")
    if not os.path.exists(PUBLISHED):
        sys.exit(f"no published manifest at {PUBLISHED} -- need its database_url")

    t0 = time.time()
    compress()

    # Hard link rather than copy: one 333 MB file on disk, reachable from both
    # the build directory and the app's resources, and re-linked here so a
    # rebuilt .gz cannot leave a stale copy behind in the bundle.
    os.makedirs(RES, exist_ok=True)
    if os.path.exists(RES_GZ):
        os.remove(RES_GZ)
    try:
        os.link(BUILD_GZ, RES_GZ)
    except OSError:                      # different volumes: fall back to a copy
        shutil.copy2(BUILD_GZ, RES_GZ)

    published = json.load(open(PUBLISHED))
    db = sqlite3.connect(DB)
    counts = {t: db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
              for t in ("message", "user")}
    db.close()

    manifest = {
        "schema_version":    published["schema_version"],
        # Where a re-download goes. The bundled copy is never fetched over the
        # network, but Settings still offers to replace it from the published one.
        "database_url":      published["database_url"],
        "compressed_size":   os.path.getsize(RES_GZ),
        "compressed_sha256": sha256(RES_GZ),
        "uncompressed_size": os.path.getsize(DB),
        "message_count":     counts["message"],
        "user_count":        counts["user"],
        "built_at":          published["built_at"],
    }
    with open(RES_MAN, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    same = manifest["compressed_sha256"] == published["compressed_sha256"]
    print(f"\nbundled: {manifest['compressed_size']/1e6:.0f} MB -> "
          f"{manifest['uncompressed_size']/1e6:.0f} MB")
    print(f"sha256:  {manifest['compressed_sha256']}")
    print(f"         {'identical to' if same else 'differs from'} the published .gz "
          f"(expected either way)")
    print(f"done in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
