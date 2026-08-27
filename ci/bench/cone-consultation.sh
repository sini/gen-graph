#!/usr/bin/env bash
# The consultation-order sweep for `coneRank`'s cyclic refusal.
#
#   ./ci/bench/cone-consultation.sh   -> per-arm readings, then ORDER-IS-LOAD-BEARING | INVALID
#
# Six arms of ONE construction (`cone-consultation.nix`), differing only in whether the
# driver's verdict is read before the memo map is entered. What each must do:
#
#   early*      exit 0, caught=true on a cyclic cone  — a named, catchable refusal
#   lateCyclic  NON-ZERO exit                         — the uncatchable abort, escaping tryEval
#   lateAcyclic exit 0, caught=false, an order        — POSITIVE CONTROL: the late
#                                                       construction is not merely broken
#
# The last line matters as much as the first: without it, a red late arm would prove only
# that something in it is broken, not that the ORDER is what broke it.
#
# ★ THE LATE ARMS' NONZERO EXIT IS READ OFF ITS SIGNATURE, NOT JUST THE CODE (den-hoag-ceiling-
# exitcode-blind-k7zcp). `lateCyclic`/`lateCycshort` used to accept ANY nonzero exit as the
# reading — a process abort for an unrelated reason (bad file, bad argument) would have read
# identically to the black-hole detector actually firing. `label` anchors on the evaluator's
# own last `error:` line (gen-scope's engine-ceiling.sh / mint-forcing.sh capture+anchor
# pattern) and only "infinite recursion encountered" counts as the expected abort; anything
# else is UNCLASSIFIED-ABORT. Note an arm-name typo does NOT probe this path here — `value`'s
# lookup is inside the file's own `tryEval`, so an unknown arm returns `caught:true, exit=0`
# rather than aborting the process; `seededTypoControl` below uses a nonexistent FILE instead,
# which aborts before any of this file's expressions run at all.
set -u
cd "$(dirname "$0")/../.." || exit 99

arm() {
  nix-instantiate --eval --strict --json --argstr arm "$1" ./ci/bench/cone-consultation.nix 2>&1
}

anchor() { # anchor <captured blob> -> the evaluator's own last `error:` line
  grep -o 'error: .*' <<<"$1" | tail -1
}

fail=0
check() { # check <arm> <expect-exit> <expect-substring-or-> — for a nonzero expect-exit, the
  # substring is checked against the ANCHORED stderr line (the abort's signature); for exit 0
  # it is checked against stdout (the returned JSON), same as before.
  out=$(arm "$1")
  rc=$?
  shown=$out
  [ "$rc" -eq 0 ] || shown=$(anchor "$out")
  if [ "$rc" -ne "$2" ]; then
    printf '%-14s exit=%d %-18s %s\n' "$1" "$rc" RC "${shown:-<no value>}"
    fail=$((fail + 1))
    return
  fi
  if [ "$3" != "-" ] && [[ "$shown" != *"$3"* ]]; then
    verdict=$([ "$rc" -eq 0 ] && echo MSG || echo UNCLASSIFIED-ABORT)
    printf '%-14s exit=%d %-18s %s\n' "$1" "$rc" "$verdict" "${shown:-<no value>}"
    fail=$((fail + 1))
    return
  fi
  printf '%-14s exit=%d %-18s %s\n' "$1" "$rc" ok "${shown:-<no value>}"
}

# A cyclic cone consulted FIRST refuses by name, and the refusal is catchable.
check earlyCyclic 0 '"caught":true'
check earlyCycshort 0 '"caught":true'
# The same construction reading the memo first: the abort escapes tryEval — the exit code AND
# the black-hole detector's own diagnosis are both the reading.
check lateCyclic 1 "infinite recursion encountered"
check lateCycshort 1 "infinite recursion encountered"
# POSITIVE CONTROLS: on an acyclic cone both orders return, and return the same order.
check earlyAcyclic 0 '"order":["p","q"]'
check lateAcyclic 0 '"order":["p","q"]'

# SEEDED CONTROL: a nonexistent bench file aborts before any expression in cone-consultation.nix
# runs at all — an unrelated reason a real "late" reading must not be confused with. If this
# read `infinite recursion encountered`, the classifier is not discriminating.
seed_out=$(nix-instantiate --eval --strict --json --argstr arm lateCyclic \
  ./ci/bench/cone-consultation-DOES-NOT-EXIST.nix 2>&1)
seed_rc=$?
seed_shown=$seed_out
[ "$seed_rc" -eq 0 ] || seed_shown=$(anchor "$seed_out")
seed_verdict=UNREACHED
if [ "$seed_rc" -eq 1 ] && [[ "$seed_shown" != *"infinite recursion encountered"* ]]; then
  seed_verdict=UNCLASSIFIED-ABORT
elif [ "$seed_rc" -eq 1 ]; then
  seed_verdict=UNEXPECTEDLY-MATCHED
fi
printf '%-14s exit=%d %-18s %s\n' seededTypo "$seed_rc" "$seed_verdict" "${seed_shown:-<no value>}"

echo
if [ "$seed_verdict" != UNCLASSIFIED-ABORT ]; then
  echo "INVALID (seeded-typo control did not read UNCLASSIFIED-ABORT — the classifier is not discriminating)"
  exit 1
fi
if [ "$fail" -eq 0 ]; then
  echo "ORDER-IS-LOAD-BEARING"
else
  echo "INVALID ($fail arms did not read as stated)"
  exit 1
fi
