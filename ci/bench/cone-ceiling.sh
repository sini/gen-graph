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
#
# ★ THE CONTROL FIRING IS READ OFF ITS SIGNATURE, NOT JUST ITS EXIT CODE (den-hoag-ceiling-
# exitcode-blind-k7zcp). A nonzero exit alone does not say the ceiling is what aborted the
# cell — a typo'd arm name aborts too, with a different diagnosis, and a blind exit-code
# check would absorb that into "controls fired" exactly like a real ceiling hit. `label`
# anchors on the evaluator's own last `error:` line (per gen-scope's engine-ceiling.sh /
# mint-forcing.sh capture+anchor pattern) and classifies it; only the EXPECTED signature
# counts as CEILING. Anything else reads UNCLASSIFIED-ABORT and is never folded into the
# controls-fired count. `seededTypoControl` below proves the classifier actually discriminates.
set -u
cd "$(dirname "$0")/../.." || exit 99

cell() { # cell <arm> <shape> <n> -> prints the reading, returns the evaluator's exit code
  nix-instantiate --eval --strict --json \
    --arg n "$3" --argstr shape "$2" --argstr arm "$1" \
    ./ci/bench/cone-ceiling.nix 2>&1
}

anchor() { # anchor <captured blob> -> the evaluator's own last `error:` line
  grep -o 'error: .*' <<<"$1" | tail -1
}

label() { # label <captured blob on a nonzero exit> -> the abort signature
  case "$(anchor "$1")" in
  *"max-call-depth exceeded"*) echo CEILING ;;
  *) echo UNCLASSIFIED-ABORT ;;
  esac
}

remediated_failures=0
controls_fired=0
controls_run=0
unclassified=0

for spec in "chain 4000" "chain 16000" "chain 32000" "deepwide 4002" "deepwide 16000" "deepwide 32000"; do
  read -r shape n <<<"$spec"
  for arm in remediated shipped; do
    out=$(cell "$arm" "$shape" "$n")
    rc=$?
    shown=$out
    [ "$rc" -eq 0 ] || shown=$(anchor "$out")
    if [ "$arm" = remediated ]; then
      printf '%-11s %-9s %-6s exit=%d %s\n' "$arm" "$shape" "$n" "$rc" "${shown:-<no value>}"
      [ "$rc" -eq 0 ] || remediated_failures=$((remediated_failures + 1))
    else
      controls_run=$((controls_run + 1))
      if [ "$rc" -eq 0 ]; then
        verdict=returned
      else
        verdict=$(label "$out")
        if [ "$verdict" = CEILING ]; then
          controls_fired=$((controls_fired + 1))
        else
          unclassified=$((unclassified + 1))
        fi
      fi
      printf '%-11s %-9s %-6s exit=%d %-18s %s\n' "$arm" "$shape" "$n" "$rc" "$verdict" "${shown:-<no value>}"
    fi
  done
done

# SEEDED CONTROL: a deliberately typo'd arm name aborts for an unrelated reason. If this read
# CEILING, the classifier above is not discriminating and every "controls fired" count is
# unearned.
seed_out=$(cell bogusArmXYZ chain 1000)
seed_rc=$?
seed_verdict=UNREACHED
if [ "$seed_rc" -ne 0 ]; then
  seed_verdict=$(label "$seed_out")
fi
seed_shown=$seed_out
[ "$seed_rc" -eq 0 ] || seed_shown=$(anchor "$seed_out")
printf '%-11s %-9s %-6s exit=%d %-18s %s\n' seededTypo chain 1000 "$seed_rc" "$seed_verdict" "${seed_shown:-<no value>}"

echo
echo "controls fired: $controls_fired/$controls_run   remediated failures: $remediated_failures   unclassified: $unclassified"
if [ "$seed_verdict" != UNCLASSIFIED-ABORT ]; then
  echo "INVALID (seeded-typo control did not read UNCLASSIFIED-ABORT — the classifier is not discriminating)"
  exit 2
fi
# A control that did not fire is not a success to absorb: it invalidates the cell it was
# supposed to arm, so the verdict is INVALID rather than a quieter REMOVED. An unclassified
# abort on a real cell is the same failure by construction — it never reached controls_fired.
if [ "$controls_fired" -ne "$controls_run" ]; then
  echo "INVALID"
  exit 2
elif [ "$remediated_failures" -ne 0 ]; then
  echo "NOT-REMOVED"
  exit 1
else
  echo "REMOVED"
fi
