#!/usr/bin/env bash
# B-109 guard: every Swift file under an xcodegen source dir must be referenced in the committed
# project.pbxproj. A file added without `xcodegen generate` (or dropped by a bad merge) is silently
# excluded from its target: the build still succeeds and its tests simply never run.
# Usage: scripts/check-pbxproj-sources.sh [path/to/project.pbxproj]   (exit 1 + list on drift)
set -euo pipefail
cd "$(dirname "$0")/.."
PBX="${1:-JournalInsight.xcodeproj/project.pbxproj}"
DIRS=(App AppTests AppUITests Widgets/Sources WatchApp/Sources WatchApp/Tests WatchWidgets/Sources)
missing=0; checked=0
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    b=$(basename "$f"); checked=$((checked + 1))
    if ! grep -qF "path = $b;" "$PBX" && ! grep -qF "path = \"$b\";" "$PBX"; then
      echo "NOT IN PBXPROJ: $f"; missing=$((missing + 1))
    fi
  done < <(find "$d" -name '*.swift' -type f)
done
if [ "$missing" -gt 0 ]; then
  echo "FAIL: $missing of $checked Swift files missing from $PBX — run \`xcodegen generate\` and commit the pbxproj"
  exit 1
fi
echo "OK: $checked Swift files all referenced in $PBX"
