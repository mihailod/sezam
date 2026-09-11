#!/bin/zsh
# Rebuild the archive database from scratch and produce the release artifacts.
#
#   ./scripts/rebuild_db.sh
#
# Every stage replays from local caches — the HTML mirror in oldsezam.net/ and
# the harvested user pages in build/users_cache/ — so this does no network I/O
# and can be re-run freely. Deleting build/users_cache would force a re-crawl of
# ~27,000 pages, so don't.
#
# Order matters: build_db.py recreates the database from nothing, which drops
# the user table, so the two user stages must follow it and link_users.py must
# come last (it rebuilds both FTS indexes and reapplies the last-seen clamp).

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/5  messages: HTML mirror -> database"
python3 -u build_db.py

echo "\n==> 2/5  users: exact-username lookups (from cache)"
python3 -u harvest_users.py

echo "\n==> 3/5  users: n-gram sweep (from cache)"
python3 -u discover_users.py --sweep 3

echo "\n==> 4/5  link users to authors, rebuild search indexes"
python3 -u link_users.py

echo "\n==> 5/5  compress + manifest"
python3 -u make_release.py

echo "\n==> done — upload build/sezam.db.gz and build/sezam-manifest.json"
