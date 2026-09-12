#!/bin/zsh
# Build, install and launch Sezam YU on the paired iPhone — the same thing as
# hitting Run in Xcode.
#
#   ./scripts/iPhone.sh setup       record the paired iPhone in .device-iphone
#   ./scripts/iPhone.sh             build, install, launch
#   ./scripts/iPhone.sh no-launch   build and install only, leave the phone alone
#
# Set SZ_IPHONE to override the recorded identifier for one run, and SZ_TEAM to
# override the signing team.
#
# Everything here is the iPhone half of the job; the build, install and launch
# themselves live in scripts/iOS.sh, shared with scripts/iPad.sh.

set -euo pipefail
cd "${0:A:h}/.."

SZ_KIND="iPhone"
SZ_DEVICE_FILE=".device-iphone"
SZ_DEVICE="${SZ_IPHONE:-}"
SZ_MATCH="iPhone"
source scripts/iOS.sh
