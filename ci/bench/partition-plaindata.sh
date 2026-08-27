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
#
# ★ `legacy`/`fnControl` FIRING IS READ OFF THE SIGNATURE, NOT JUST THE EXIT CODE (den-hoag-
# ceiling-exitcode-blind-k7zcp). A nonzero exit alone does not say the JSON-crossability
# failure is what aborted the cell — a typo'd arm name aborts too, with an unrelated
# diagnosis, and a blind exit-code check would count that as a fired control just the same.
# `label` anchors on the evaluator's own last `error:` line (gen-scope's engine-ceiling.sh /
# mint-forcing.sh capture+anchor pattern) and only the expected "cannot convert a function to
# JSON" counts as CROSSABILITY-BLOCKED; anything else reads UNCLASSIFIED-ABORT and is never
# folded into controls_fired. `seededTypoControl` proves the classifier discriminates.
set -u
cd "$(dirname "$0")/../.." || exit 99

cell() { # cell <arm> <shape> <n> -> prints the reading, returns the evaluator's exit code
  nix-instantiate --eval --strict --json \
    --arg n "$3" --argstr shape "$2" --argstr arm "$1" \
    ./ci/bench/partition-plaindata.nix 2>&1
}

anchor() { # anchor <captured blob> -> the evaluator's own last `error:` line
  grep -o 'error: .*' <<<"$1" | tail -1
}

label() { # label <captured blob on a nonzero exit> -> the abort signature
  case "$(anchor "$1")" in
  *"cannot convert a function to JSON"*) echo CROSSABILITY-BLOCKED ;;
  *) echo UNCLASSIFIED-ABORT ;;
  esac
}

failures=0
controls_fired=0
controls_run=0
unclassified=0

for shape in chain cycle fleet; do
  for arm in door fbNode fbWork closure; do
    out=$(cell "$arm" "$shape" 60)
    rc=$?
    shown=$out
    [ "$rc" -eq 0 ] || shown=$(anchor "$out")
    printf '%-10s %-6s exit=%d %s\n' "$arm" "$shape" "$rc" "${shown:-<no value>}"
    [ "$rc" -eq 0 ] || failures=$((failures + 1))
  done
  out=$(cell legacy "$shape" 60)
  rc=$?
  controls_run=$((controls_run + 1))
  if [ "$rc" -eq 0 ]; then
    verdict=returned
  else
    verdict=$(label "$out")
    if [ "$verdict" = CROSSABILITY-BLOCKED ]; then
      controls_fired=$((controls_fired + 1))
    else
      unclassified=$((unclassified + 1))
    fi
  fi
  shown=$out
  [ "$rc" -eq 0 ] || shown=$(anchor "$out")
  printf '%-10s %-6s exit=%d %-19s %s\n' legacy "$shape" "$rc" "$verdict" "${shown:-<no value>}"
done

out=$(cell fnControl chain 60)
rc=$?
controls_run=$((controls_run + 1))
if [ "$rc" -eq 0 ]; then
  verdict=returned
else
  verdict=$(label "$out")
  if [ "$verdict" = CROSSABILITY-BLOCKED ]; then
    controls_fired=$((controls_fired + 1))
  else
    unclassified=$((unclassified + 1))
  fi
fi
shown=$out
[ "$rc" -eq 0 ] || shown=$(anchor "$out")
printf '%-10s %-6s exit=%d %-19s %s\n' fnControl chain "$rc" "$verdict" "${shown:-<no value>}"

out=$(cell okControl chain 60)
rc=$?
printf '%-10s %-6s exit=%d %s\n' okControl chain "$rc" "${out:-<no value>}"
[ "$rc" -eq 0 ] || controls_run=$((controls_run + 1))

# SEEDED CONTROL: a deliberately typo'd arm name aborts for an unrelated reason. If this read
# CROSSABILITY-BLOCKED, the classifier above is not discriminating and every "controls fired"
# count above is unearned.
seed_out=$(cell bogusArmXYZ chain 60)
seed_rc=$?
seed_verdict=UNREACHED
[ "$seed_rc" -ne 0 ] && seed_verdict=$(label "$seed_out")
seed_shown=$seed_out
[ "$seed_rc" -eq 0 ] || seed_shown=$(anchor "$seed_out")
printf '%-10s %-6s exit=%d %-19s %s\n' seededTypo chain "$seed_rc" "$seed_verdict" "${seed_shown:-<no value>}"

echo
echo "controls fired: $controls_fired/$controls_run   failures: $failures   unclassified: $unclassified"
if [ "$seed_verdict" != UNCLASSIFIED-ABORT ]; then
  echo "INVALID (seeded-typo control did not read UNCLASSIFIED-ABORT — the classifier is not discriminating)"
  exit 2
fi
if [ "$controls_fired" -ne "$controls_run" ]; then
  echo "INVALID"
  exit 2
elif [ "$failures" -ne 0 ]; then
  echo "DOES-NOT-CROSS"
  exit 1
else
  echo "CROSSES"
fi
