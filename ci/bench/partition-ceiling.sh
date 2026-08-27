#!/usr/bin/env bash
# The partition arms' ceiling sweep: an EXIT-CODE instrument, because the thing being measured
# is an abort no in-language assertion can observe.
#
#   ./ci/bench/partition-ceiling.sh     -> per-cell readings, then CEILING-FREE | CEILING-FOUND
#                                          | INVALID
#
# THREE ARMS PER CELL. `fbNode` and `fbWork` are the two published forward–backward arms;
# `unforced` is the worklist arm written so that its tag map is written every round and read in
# none, which is the construction whose accumulator chains. The third is a LIVE NEGATIVE
# CONTROL for the forcing question, not a historical curiosity.
#
# ★ THE UNFORCED CONTROL'S OWN BOUNDARY IS BISECTED AND IT IS NOT WHERE A READER WOULD EXPECT.
# On this instrument it returns at 44,150 COMPONENTS and aborts at 44,160 — `stack overflow`, on
# the C stack — because its per-component step is an attrset UPDATE, and the update operator does
# not increment the evaluator's call-depth counter. Those are component counts read off the
# cells themselves (`components` in the returned record), not the `n` arguments that produced
# them: `fleet` builds `n / 10` chains of ten, so it realises components in multiples of ten and
# an `n` of 44,159 is a fixture of 44,150. State the axis the file's own rows state.
#
# A per-component step that is a FUNCTION APPLICATION dies far earlier, and that figure is an
# UPPER BOUND under a stated measuring expression rather than a constant: a self-applying
# recursion in a BARE `-E` expression returns at depth 9,998 and aborts at 9,999, while the same
# recursion in a function-headed file taking one `--arg` returns at 9,997 and aborts at 9,998.
# The one-frame gap IS the evaluation-context axis — the call-depth budget is shared with every
# frame already open above the recursion — so a consumer's real boundary is strictly lower than
# any figure quoted here. Both mechanisms are real and they are DIFFERENT axes, so a component
# count alone does not say which one a construction is on. The cells below therefore state their
# component counts, and the sweep's VALIDITY rests on `abortControl`, whose depth is fixed
# rather than scaled to the cell.
#
# A cell in which `abortControl` does not fire is INVALID, never a pass: it says the evaluation
# could not have observed an abort at all, so a green row from it means nothing.
#
# `nix eval --file` is not usable: it does not auto-call a function-headed file. Every cell is
# `nix-instantiate --eval --strict --json` with explicit `--arg`/`--argstr`, and every exit code
# is read IMMEDIATELY — `$?` after a pipe reads the pipe's last stage and is a false green.
#
# ★ `abortControl` FIRING IS READ OFF ITS SIGNATURE, NOT JUST ITS EXIT CODE (den-hoag-ceiling-
# exitcode-blind-k7zcp). A nonzero exit alone does not say the call-depth ceiling is what
# aborted the cell — a typo'd arm name aborts too, and a blind exit-code check would count
# that as a fired control just the same. `label` anchors on the evaluator's own last `error:`
# line (gen-scope's engine-ceiling.sh:34-36 capture+anchor pattern) and classifies it — CALLDEPTH
# checked BEFORE the generic CSTACK, same ordering and same reason as gen-scope's: this
# instrument's own `max-call-depth exceeded` reading arrives as `stack overflow; max-call-depth
# exceeded`, so the generic substring is present on the SPECIFIC signature too. Anything else
# reads UNCLASSIFIED-ABORT and is never folded into controls_fired. `unforced` gets the same
# label shown (informational — it is CSTACK's own live case, see the header above), and
# `seededTypoControl` proves the classifier discriminates.
set -u
cd "$(dirname "$0")/../.." || exit 99

cell() { # cell <arm> <shape> <n> -> prints the reading, returns the evaluator's exit code
  nix-instantiate --eval --strict --json \
    --arg n "$3" --argstr shape "$2" --argstr arm "$1" \
    ./ci/bench/partition-ceiling.nix 2>&1
}

anchor() { # anchor <captured blob> -> the evaluator's own last `error:` line
  grep -o 'error: .*' <<<"$1" | tail -1
}

label() { # label <captured blob on a nonzero exit> -> the abort signature
  case "$(anchor "$1")" in
  *"max-call-depth exceeded"*) echo CALLDEPTH ;;
  *"stack overflow"*) echo CSTACK ;;
  *) echo UNCLASSIFIED-ABORT ;;
  esac
}

arm_failures=0
controls_fired=0
controls_run=0
unclassified=0

for spec in "chain 1000" "chain 4000" "cycle 1000" "cycle 4000" "fleet 16000" "fleet 64000"; do
  read -r shape n <<<"$spec"
  for arm in fbNode fbWork unforced; do
    out=$(cell "$arm" "$shape" "$n")
    rc=$?
    shown=$out
    reading=returned
    if [ "$rc" -ne 0 ]; then
      shown=$(anchor "$out")
      reading=$(label "$out")
    fi
    printf '%-9s %-6s %-6s exit=%d %-18s %s\n' "$arm" "$shape" "$n" "$rc" "${reading}" "${shown:-<no value>}"
    if [ "$arm" != unforced ]; then
      [ "$rc" -eq 0 ] || arm_failures=$((arm_failures + 1))
    fi
  done
  # The validity control, run at EVERY cell rather than once per sweep: an evaluation that
  # cannot abort is what a false green looks like, and it is a per-evaluation property. Firing
  # requires the EXPECTED signature — CALLDEPTH — not merely a nonzero exit.
  out=$(cell abortControl "$shape" "$n")
  rc=$?
  controls_run=$((controls_run + 1))
  if [ "$rc" -eq 0 ]; then
    verdict=returned
  else
    verdict=$(label "$out")
    if [ "$verdict" = CALLDEPTH ]; then
      controls_fired=$((controls_fired + 1))
    else
      unclassified=$((unclassified + 1))
    fi
  fi
  shown=$out
  [ "$rc" -eq 0 ] || shown=$(anchor "$out")
  printf '%-9s %-6s %-6s exit=%d %-18s %s\n' abortControl "$shape" "$n" "$rc" "$verdict" "${shown:-<no value>}"
done

# The catcher's own positive control, so an abort reading is not confused with a broken
# evaluation: these two must return, or nothing above is readable.
for arm in okControl catchControl; do
  out=$(cell "$arm" chain 1000)
  rc=$?
  printf '%-9s %-6s %-6s exit=%d %s\n' "$arm" chain 1000 "$rc" "${out:-<no value>}"
  [ "$rc" -eq 0 ] || controls_run=$((controls_run + 2))
done

# SEEDED CONTROL: a deliberately typo'd arm name aborts for an unrelated reason. If this read
# CALLDEPTH or CSTACK, the classifier above is not discriminating and every "controls fired"
# count is unearned.
seed_out=$(cell bogusArmXYZ chain 1000)
seed_rc=$?
seed_verdict=UNREACHED
[ "$seed_rc" -ne 0 ] && seed_verdict=$(label "$seed_out")
seed_shown=$seed_out
[ "$seed_rc" -eq 0 ] || seed_shown=$(anchor "$seed_out")
printf '%-9s %-6s %-6s exit=%d %-18s %s\n' seededTypo chain 1000 "$seed_rc" "$seed_verdict" "${seed_shown:-<no value>}"

echo
echo "controls fired: $controls_fired/$controls_run   arm failures: $arm_failures   unclassified: $unclassified"
if [ "$seed_verdict" != UNCLASSIFIED-ABORT ]; then
  echo "INVALID (seeded-typo control did not read UNCLASSIFIED-ABORT — the classifier is not discriminating)"
  exit 2
fi
if [ "$controls_fired" -ne "$controls_run" ]; then
  echo "INVALID"
  exit 2
elif [ "$arm_failures" -ne 0 ]; then
  echo "CEILING-FOUND"
  exit 1
else
  echo "CEILING-FREE"
fi
