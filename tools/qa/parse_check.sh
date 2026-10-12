#!/bin/bash
# QA §1.1: Parse-check every .gd file (Godot 4.7.2, --check-only --script).
# Usage: ./tools/qa/parse_check.sh
cd "$(dirname "$0")/../.."
GODOT=~/godot/Godot_v4.7.2-stable_linux.x86_64
FAIL=0
COUNT=0
while IFS= read -r f; do
  COUNT=$((COUNT+1))
  OUT=$($GODOT --headless --check-only --script "$f" 2>&1 | grep "SCRIPT ERROR" | head -3)
  if [ -n "$OUT" ]; then
    echo "FAIL: $f"
    echo "$OUT"
    FAIL=$((FAIL+1))
  fi
done < <(find scripts -name "*.gd")
echo "Checked $COUNT files, $FAIL failures"
exit $FAIL
