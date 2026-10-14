#!/bin/zsh
# Generate + build for the selected simulator. Usage: scripts/build.sh [simulator-id]
set -euo pipefail
cd "${0:A:h}/.."
SIM=${1:-3C864AD4-9C80-44BF-8B1C-EB57732C2C9C}
RUN=$(date +%Y%m%d-%H%M%S)
mkdir -p build/evidence
./scripts/generate.sh
set -o pipefail
xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "build/evidence/build-$RUN.log" \
  | grep -E "error:|warning: .*/(Roam|RoamTests|RoamUITests)/|BUILD SUCCEEDED|BUILD FAILED" | sort -u
