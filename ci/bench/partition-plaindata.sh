#!/usr/bin/env bash
# The partition door's PLAIN-DATA sweep: an EXIT-CODE instrument, because the failure mode is
# an uncatchable abort.
#
#   ./ci/bench/partition-plaindata.sh   -> per-cell readings, then CROSSES | DOES-NOT-CROSS
#                                          | INVALID
#
# The property is direct rather than proxied: `builtins.toJSON` of the WHOLE result returns.
# Every published arm is read on every shape, and two ARMED CONTROLS run in the same sweep:
# `legacy` — the same partition published with its lookups as FUNCTIONS, which must FAIL — and
# `fnControl` — `tryEval` over `toJSON` of a bare function, which must ESCAPE the catcher. A
# sweep in which either returns is INVALID, never a pass: the first would mean the cell is not
# reading crossability, the second would mean the failure is catchable and this whole
# instrument is the wrong shape.
#
# `okControl` is the catcher's live positive control. Without it, `fnControl`'s exit 1 could be
# a broken `tryEval` rather than an escaping abort.
#
# Exit codes are read IMMEDIATELY — `$?` after a pipe reads the pipe's last stage.
set -u
cd "$(dirname "$0")/../.." || exit 99

cell() { # cell <arm> <shape> <n> -> prints the reading, returns the evaluator's exit code
  nix-instantiate --eval --strict --json \
    --arg n "$3" --argstr shape "$2" --argstr arm "$1" \
    ./ci/bench/partition-plaindata.nix 2>/dev/null
}

failures=0
controls_fired=0
controls_run=0

for shape in chain cycle fleet; do
  for arm in door fbNode fbWork closure; do
    out=$(cell "$arm" "$shape" 60)
    rc=$?
    printf '%-10s %-6s exit=%d %s\n' "$arm" "$shape" "$rc" "${out:-<no value>}"
    [ "$rc" -eq 0 ] || failures=$((failures + 1))
  done
  out=$(cell legacy "$shape" 60)
  rc=$?
  controls_run=$((controls_run + 1))
  [ "$rc" -eq 0 ] || controls_fired=$((controls_fired + 1))
  printf '%-10s %-6s exit=%d %s\n' legacy "$shape" "$rc" "${out:-<no value>}"
done

out=$(cell fnControl chain 60)
rc=$?
controls_run=$((controls_run + 1))
[ "$rc" -eq 0 ] || controls_fired=$((controls_fired + 1))
printf '%-10s %-6s exit=%d %s\n' fnControl chain "$rc" "${out:-<no value>}"

out=$(cell okControl chain 60)
rc=$?
printf '%-10s %-6s exit=%d %s\n' okControl chain "$rc" "${out:-<no value>}"
[ "$rc" -eq 0 ] || controls_run=$((controls_run + 1))

echo
echo "controls fired: $controls_fired/$controls_run   failures: $failures"
if [ "$controls_fired" -ne "$controls_run" ]; then
  echo "INVALID"
  exit 2
elif [ "$failures" -ne 0 ]; then
  echo "DOES-NOT-CROSS"
  exit 1
else
  echo "CROSSES"
fi
