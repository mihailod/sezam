#!/bin/zsh
# Build, install and launch Sezam BBS on the paired iPad — the same thing as
# hitting Run in Xcode.
#
#   ./scripts/iPad.sh setup         record the paired iPad in .device-ipad
#   ./scripts/iPad.sh               build, install, launch
#   ./scripts/iPad.sh no-launch     build and install only, leave the iPad alone
#
# Set SZ_IPAD to override the recorded identifier for one run, and SZ_TEAM to
# override the signing team.
#
# The product is the same universal binary the iPhone gets — one build covers
# both idioms — so the two scripts differ only in which device they look for
# and where they record it. The rest lives in scripts/iOS.sh.

set -euo pipefail
cd "${0:A:h}/.."

SZ_KIND="iPad"
SZ_DEVICE_FILE=".device-ipad"
SZ_DEVICE="${SZ_IPAD:-}"
SZ_MATCH="iPad"
source scripts/iOS.sh
