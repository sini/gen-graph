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
set -u
cd "$(dirname "$0")/../.." || exit 99

arm() {
  nix-instantiate --eval --strict --json --argstr arm "$1" ./ci/bench/cone-consultation.nix 2>/dev/null
}

fail=0
check() { # check <arm> <expect-exit> <expect-substring-or-->
  out=$(arm "$1")
  rc=$?
  printf '%-14s exit=%d %s\n' "$1" "$rc" "${out:-<no value>}"
  if [ "$rc" -ne "$2" ]; then
    fail=$((fail + 1))
    return
  fi
  if [ "$3" != "-" ] && [[ "$out" != *"$3"* ]]; then
    fail=$((fail + 1))
  fi
}

# A cyclic cone consulted FIRST refuses by name, and the refusal is catchable.
check earlyCyclic 0 '"caught":true'
check earlyCycshort 0 '"caught":true'
# The same construction reading the memo first: the abort escapes tryEval, so there is no
# JSON to read and the exit code is the whole reading.
check lateCyclic 1 -
check lateCycshort 1 -
# POSITIVE CONTROLS: on an acyclic cone both orders return, and return the same order.
check earlyAcyclic 0 '"order":["p","q"]'
check lateAcyclic 0 '"order":["p","q"]'

echo
if [ "$fail" -eq 0 ]; then
  echo "ORDER-IS-LOAD-BEARING"
else
  echo "INVALID ($fail arms did not read as stated)"
  exit 1
fi
