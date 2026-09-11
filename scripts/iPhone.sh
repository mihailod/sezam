#!/bin/zsh
# Build, install and launch Sezam YU on the paired iPhone — the same thing as
# hitting Run in Xcode.
#
#   ./scripts/iPhone.sh setup       record the paired iPhone in .device-iphone
#   ./scripts/iPhone.sh             build, install, launch
#   ./scripts/iPhone.sh no-launch   build and install only, leave the phone alone
#
# iPhone is the only supported target, so there is no per-device wrapper here:
# the device-specific bits are inline rather than passed through the
# environment. Set SZ_IPHONE to override the recorded identifier for one run,
# and SZ_TEAM to override the signing team.
#
# This is a development install only. Packaging, signing for distribution,
# notarising and uploading stay manual.
#
# The build is `generic/platform=iOS`, so the phone need not be present at build
# time — only the install needs it. Derived data is kept separate from the
# simulator's (app/build/DerivedData) so a device build never invalidates that
# one, and vice versa.
#
# NOTE (zsh): argument lists are arrays expanded as "${arr[@]}". An unquoted
# scalar does not word-split in zsh and silently becomes one argv token.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_DIR="app"
PROJECT="SezamYU.xcodeproj"
SCHEME="SezamYU"
BUNDLE="net.oldsezam.reader"
APP_NAME="Sezam YU.app"          # PRODUCT_NAME has a space — quote every use
DEVICE_FILE=".device-iphone"
DERIVED=".xcbuild-device"
# Release rather than the Debug default: this script is how the app reaches the
# phone for everyday use, and the Users tab's first open measured ~240 ms of
# main-thread work unoptimised against ~130 ms optimised.
CONFIG="Release"

# The device identifier lives in a gitignored file — it names a specific piece
# of hardware and belongs to this machine, not the repository.
if [[ "${1:-}" == "setup" ]]; then
  # Matched by shape, not by column: both the name and model columns contain
  # spaces, so counting fields picks up a fragment of the model name.
  #
  # Both reachable states count here, not just "connected" — see the state
  # check below for why.
  id=$(xcrun devicectl list devices 2>/dev/null \
       | grep -E 'connected|available' | grep -i 'iPhone' \
       | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' | head -1)
  [[ -n "$id" ]] || { echo "no reachable iPhone found — plug it in or wake it"; exit 1; }
  print -r -- "$id" > "$DEVICE_FILE"
  echo "==> wrote $DEVICE_FILE ($id)"
  exit 0
fi

DEVICE="${SZ_IPHONE:-}"
if [[ -z "$DEVICE" && -r "$DEVICE_FILE" ]]; then
  DEVICE=$(< "$DEVICE_FILE")
  DEVICE="${DEVICE//[[:space:]]/}"
fi
if [[ -z "$DEVICE" ]]; then
  echo "no device configured — run: ./scripts/iPhone.sh setup"
  echo "(or set SZ_IPHONE to a device identifier)"
  exit 1
fi

state=$(xcrun devicectl list devices 2>/dev/null | awk -v d="$DEVICE" '$0 ~ d {print}')
if [[ -z "$state" ]]; then
  echo "==> iPhone not paired with this Mac (looked for $DEVICE)"
  echo "    plug it in, or set SZ_IPHONE to another device identifier"
  exit 1
fi
# Two states can be installed to, and only one of them says "connected":
# a cabled device reports "connected", while one reachable over the network
# reports "available (paired)". Checking for "connected" alone refuses every
# wireless deploy. "unavailable" is the paired-but-out-of-reach case, and is
# the one to refuse.
if [[ "$state" != *connected* && "$state" != *available* ]]; then
  echo "==> iPhone is paired but not reachable — plug it in, or put it on the"
  echo "    same network with Xcode's network debugging enabled"
  exit 1
fi

# The .xcodeproj is generated from project.yml and is gitignored, so it may not
# exist at all on a fresh clone — and if project.yml has been edited since, it
# is stale. Regenerating is cheap; a stale project silently builds old sources.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not installed — brew install xcodegen"
  exit 1
fi
if [[ ! -d "$APP_DIR/$PROJECT" || "$APP_DIR/project.yml" -nt "$APP_DIR/$PROJECT" ]]; then
  echo "==> generating $PROJECT from project.yml"
  ( cd "$APP_DIR" && xcodegen generate >/dev/null )
fi

# `-allowProvisioningUpdates` lets xcodebuild fetch or refresh a profile itself.
# Without it xcodebuild only uses a profile already cached on this Mac, so the
# first device build — and any build after the App ID's capabilities change —
# fails until Xcode is opened once to do the fetch.
#
# DEVELOPMENT_TEAM is only passed when known: with a single team configured,
# automatic signing resolves it without help.
args=(-project "$APP_DIR/$PROJECT" -scheme "$SCHEME"
      -destination "generic/platform=iOS"
      -configuration "$CONFIG" -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build)
TEAM="${SZ_TEAM:-}"
[[ -z "$TEAM" && -r .team ]] && TEAM=$(< .team) && TEAM="${TEAM//[[:space:]]/}"
[[ -n "$TEAM" ]] && args+=("DEVELOPMENT_TEAM=$TEAM")

echo "==> building for device"
if ! xcodebuild "${args[@]}"; then
  echo "==> build failed — if it is a signing error, set your team once:"
  echo "    echo ABCDE12345 > .team      (Apple Developer Team ID)"
  exit 1
fi

# Named exactly rather than found: earlier Debug builds are still in $DERIVED,
# and a search for the .app could install one of those instead of this build.
app="$DERIVED/Build/Products/$CONFIG-iphoneos/$APP_NAME"
[[ -d "$app" ]] || { echo "no .app produced at $app"; exit 1; }

# Installing over the existing app keeps its data container, so the downloaded
# archive survives the update — reinstalling would otherwise mean waiting for
# the whole database to download again.
echo "==> installing on iPhone"
if ! xcrun devicectl device install app --device "$DEVICE" "$app" 2>&1 | tail -3; then
  echo "==> install failed — the iPhone must be unlocked to accept it"
  exit 1
fi

# Launching by default mirrors what Run in Xcode does. Terminate first:
# launching an already-running app just foregrounds the old process, so without
# this you would be looking at the previous build and think nothing had landed.
if [[ "${1:-}" != "no-launch" ]]; then
  echo "==> launching"
  xcrun devicectl device process terminate \
    --device "$DEVICE" --bundle-identifier "$BUNDLE" >/dev/null 2>&1 || true
  xcrun devicectl device process launch \
    --device "$DEVICE" --terminate-existing "$BUNDLE" >/dev/null
fi
echo "==> done"
