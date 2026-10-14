#!/bin/zsh
# Exports named screenshot attachments from an .xcresult bundle into screenshots/<milestone>/.
# Usage: scripts/export-screenshots.sh build/results/tests-<run>.xcresult m1
set -euo pipefail
cd "${0:A:h}/.."
result="$1"; milestone="$2"
tmp=$(mktemp -d)
xcrun xcresulttool export attachments --path "$result" --output-path "$tmp" >/dev/null
mkdir -p "screenshots/$milestone"
python3 - "$tmp" "screenshots/$milestone" "$milestone" <<'PY'
import json, os, shutil, sys
src, dst, milestone = sys.argv[1:4]
manifest = json.load(open(os.path.join(src, "manifest.json")))
count = 0
for test in manifest:
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName") or attachment["exportedFileName"]
        base = name.split("_")[0] if "_" in name else os.path.splitext(name)[0]
        if not base.startswith(milestone + "-"):
            continue
        target = os.path.join(dst, base[len(milestone) + 1:] + ".png")
        shutil.copyfile(os.path.join(src, attachment["exportedFileName"]), target)
        count += 1
print(f"exported {count} screenshots to {dst}")
PY
rm -rf "$tmp"
