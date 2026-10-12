#!/bin/bash
# QA §1.6: Verify laser teleport in all 11 MARIGOLD scenes.
# Greps for the teleport rig call in each chapter script.
cd "$(dirname "$0")/../.."
SCENES="ch1_ofrenda ch2_bridge ch3_alebrijes ch4_papel ch5_baile espejo galeria guitarra mano_magica ofrenda_finale pinta"
FAIL=0
for s in $SCENES; do
  f="scripts/chapters/$s.gd"
  if grep -q "MarigoldTeleport.laser_begin" "$f"; then
    echo "OK: $s"
  else
    echo "FAIL: $s missing laser_begin"
    FAIL=$((FAIL+1))
  fi
done
echo "Failures: $FAIL"
exit $FAIL
