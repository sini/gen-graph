#!/usr/bin/env bash
# The `coneRank` ceiling sweep: an EXIT-CODE instrument, because the thing being measured is
# an abort no in-language assertion can observe.
#
#   ./ci/bench/cone-ceiling.sh          -> per-cell readings, then REMOVED | NOT-REMOVED | INVALID
#
# Every cell is run twice in the same sweep: the library's `coneRank` and the
# PRE-REMEDIATION construction beside it. The second is a LIVE NEGATIVE CONTROL — it must
# ABORT at every cell, or the sizes never reached the ceiling and the run says nothing about
# the first. A sweep in which no control fires is INVALID, never a pass; that is the whole
# reason both arms run here rather than one arm against a remembered figure.
#
# `nix eval --file` is not usable: it does not auto-call a function-headed file. Every cell
# is `nix-instantiate --eval --strict --json` with explicit `--arg`/`--argstr`.
set -u
cd "$(dirname "$0")/../.." || exit 99

cell() { # cell <arm> <shape> <n> -> prints the reading, returns the evaluator's exit code
  nix-instantiate --eval --strict --json \
    --arg n "$3" --argstr shape "$2" --argstr arm "$1" \
    ./ci/bench/cone-ceiling.nix 2>/dev/null
}

remediated_failures=0
controls_fired=0
controls_run=0

for spec in "chain 4000" "chain 16000" "chain 32000" "deepwide 4002" "deepwide 16000" "deepwide 32000"; do
  read -r shape n <<<"$spec"
  for arm in remediated shipped; do
    out=$(cell "$arm" "$shape" "$n")
    rc=$?
    printf '%-11s %-9s %-6s exit=%d %s\n' "$arm" "$shape" "$n" "$rc" "${out:-<no value>}"
    if [ "$arm" = remediated ]; then
      [ "$rc" -eq 0 ] || remediated_failures=$((remediated_failures + 1))
    else
      controls_run=$((controls_run + 1))
      [ "$rc" -eq 0 ] || controls_fired=$((controls_fired + 1))
    fi
  done
done

echo
echo "controls fired: $controls_fired/$controls_run   remediated failures: $remediated_failures"
# A control that did not fire is not a success to absorb: it invalidates the cell it was
# supposed to arm, so the verdict is INVALID rather than a quieter REMOVED.
if [ "$controls_fired" -ne "$controls_run" ]; then
  echo "INVALID"
  exit 2
elif [ "$remediated_failures" -ne 0 ]; then
  echo "NOT-REMOVED"
  exit 1
else
  echo "REMOVED"
fi
