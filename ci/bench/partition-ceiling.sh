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
set -u
cd "$(dirname "$0")/../.." || exit 99

cell() { # cell <arm> <shape> <n> -> prints the reading, returns the evaluator's exit code
  nix-instantiate --eval --strict --json \
    --arg n "$3" --argstr shape "$2" --argstr arm "$1" \
    ./ci/bench/partition-ceiling.nix 2>/dev/null
}

arm_failures=0
controls_fired=0
controls_run=0

for spec in "chain 1000" "chain 4000" "cycle 1000" "cycle 4000" "fleet 16000" "fleet 64000"; do
  read -r shape n <<<"$spec"
  for arm in fbNode fbWork unforced; do
    out=$(cell "$arm" "$shape" "$n")
    rc=$?
    printf '%-9s %-6s %-6s exit=%d %s\n' "$arm" "$shape" "$n" "$rc" "${out:-<no value>}"
    if [ "$arm" != unforced ]; then
      [ "$rc" -eq 0 ] || arm_failures=$((arm_failures + 1))
    fi
  done
  # The validity control, run at EVERY cell rather than once per sweep: an evaluation that
  # cannot abort is what a false green looks like, and it is a per-evaluation property.
  out=$(cell abortControl "$shape" "$n")
  rc=$?
  controls_run=$((controls_run + 1))
  [ "$rc" -eq 0 ] || controls_fired=$((controls_fired + 1))
  printf '%-9s %-6s %-6s exit=%d %s\n' abortControl "$shape" "$n" "$rc" "${out:-<no value>}"
done

# The catcher's own positive control, so an abort reading is not confused with a broken
# evaluation: these two must return, or nothing above is readable.
for arm in okControl catchControl; do
  out=$(cell "$arm" chain 1000)
  rc=$?
  printf '%-9s %-6s %-6s exit=%d %s\n' "$arm" chain 1000 "$rc" "${out:-<no value>}"
  [ "$rc" -eq 0 ] || controls_run=$((controls_run + 2))
done

echo
echo "controls fired: $controls_fired/$controls_run   arm failures: $arm_failures"
if [ "$controls_fired" -ne "$controls_run" ]; then
  echo "INVALID"
  exit 2
elif [ "$arm_failures" -ne 0 ]; then
  echo "CEILING-FOUND"
  exit 1
else
  echo "CEILING-FREE"
fi
