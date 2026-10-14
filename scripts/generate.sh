#!/bin/zsh
# Regenerates Roam.xcodeproj from project.yml and restores the committed SwiftPM pins.
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --spec project.yml --quiet
mkdir -p Roam.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Config/Package.resolved Roam.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
