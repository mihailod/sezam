#!/bin/zsh
# Reclaim the disk that installing this app on a simulator leaves behind.
#
#   ./scripts/sim_gc.sh              # purge dead simulator containers
#   ./scripts/sim_gc.sh --products   # also delete built .app bundles
#
# Every `simctl install` replaces the app's bundle container and moves the old
# one to Library/Caches/com.apple.containermanagerd/Dead, where it sits until
# the simulator feels like collecting it. That was fine when the app was 10 MB.
# Now it ships a 333 MB archive, so ten reinstalls strand 3.3 GB.
#
# Deleting these is safe: they are containers iOS has already unlinked from
# every installed app, and it deletes them itself eventually. Nothing here
# touches a live container, so installed apps keep their data.
#
# --products additionally removes built .app bundles from the two build trees.
# Those are regenerable and each carries its own copy of the archive; the next
# build recreates whichever it needs.

set -euo pipefail
cd "$(dirname "$0")/.."

# Totalled from what is actually removed, not from a df delta: APFS reclaims
# space lazily, so free space right after a delete reads back roughly unchanged
# (a measured run reported "-1 MB" having just freed 330).
freed_kb=0

devices=~/Library/Developer/CoreSimulator/Devices
dead_dirs=()
while IFS= read -r d; do dead_dirs+=("$d"); done < <(
    find "$devices" -maxdepth 6 -type d -name Dead 2>/dev/null)

for d in "${dead_dirs[@]}"; do
    entries=$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    [[ "$entries" == "0" ]] && continue
    size=$(du -sh "$d" 2>/dev/null | cut -f1)
    freed_kb=$(( freed_kb + $(du -sk "$d" 2>/dev/null | cut -f1) ))
    echo "purging $entries dead container(s), $size"
    # Delete the contents, not the directory: containermanagerd owns it and
    # recreates it, but removing it out from under a booted simulator is rude.
    find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
done

if [[ "${1:-}" == "--products" ]]; then
    products=()
    while IFS= read -r p; do products+=("$p"); done < <(
        find .xcbuild-device app/build -maxdepth 4 -type d -name "*.app" 2>/dev/null)
    for p in "${products[@]}"; do
        echo "removing build product $(du -sh "$p" 2>/dev/null | cut -f1)  $p"
        freed_kb=$(( freed_kb + $(du -sk "$p" 2>/dev/null | cut -f1) ))
        rm -rf "$p"
    done
fi

free_gb=$(df -m /System/Volumes/Data | tail -1 | awk '{printf "%.1f", $4 / 1024}')
if (( freed_kb >= 1024 * 1024 )); then
    printf 'reclaimed %.1f GB  (free: %s GB)\n' $(( freed_kb / 1048576.0 )) "$free_gb"
else
    printf 'reclaimed %d MB  (free: %s GB)\n' $(( freed_kb / 1024 )) "$free_gb"
fi
