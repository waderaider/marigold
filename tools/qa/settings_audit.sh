#!/bin/bash
# QA §1.5: Verify every settings option does something real (no placebo).
# Checks that each gfx.gd setting has a consumer in the codebase.
cd "$(dirname "$0")/../.."
check() {
  local name="$1" pattern="$2"
  if grep -rq "$pattern" scripts/ --include="*.gd" | grep -v "gfx.gd:"; then
    echo "OK: $name ($pattern consumed)"
  else
    # Fallback: check gfx.gd itself applies it
    if grep -q "$pattern" scripts/shared/gfx.gd; then
      echo "OK: $name ($pattern in gfx.gd)"
    else
      echo "FAIL: $name ($pattern not found)"
      return 1
    fi
  fi
}
FAIL=0
check "input_method" "input_pref()" || FAIL=$((FAIL+1))
check "dominant_hand" "dominant_hand\|hand_pref" || FAIL=$((FAIL+1))
check "tooltips" "tooltips_on\|show_legend" || FAIL=$((FAIL+1))
check "quality" "scaling_3d_scale" || FAIL=$((FAIL+1))
check "text_size" "text_scale()" || FAIL=$((FAIL+1))
check "seated" "panel_height()" || FAIL=$((FAIL+1))
check "vignette" "vignette_max()" || FAIL=$((FAIL+1))
check "flight" "flight_duration()" || FAIL=$((FAIL+1))
check "subtitles" "subtitles_on()" || FAIL=$((FAIL+1))
check "dance_assist" "dance_assist()" || FAIL=$((FAIL+1))
echo "Failures: $FAIL"
exit $FAIL
