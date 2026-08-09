#!/usr/bin/env bash
# Reads the harness sentinel in `cost-classes.nix` and prints its classification.
#
# Two passes, because a Nix expression cannot observe its own allocation: pass one measures
# the three pinned cells under NIX_SHOW_STATS, pass two hands those readings back to the
# bench file, which owns both the pins and the classifier. Nothing about the verdict is
# decided in this script — it is a transport, so the guard cannot drift from the file it
# guards.
#
#   ./ci/bench/sentinel.sh            -> STABLE | SHIFTED-BENIGN | SHIFTED-STRUCTURAL | UNUSABLE
#
# ★ A missing or non-integer reading is UNUSABLE and NEVER STABLE: a sentinel that did not
# run must not report that nothing moved. The classifier enforces that; this script must not
# paper over a failed cell by substituting a zero.
set -u
cd "$(dirname "$0")/../.." || exit 99
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cell() { # cell <armName> -> "list sets nrLookups", or "" if the cell did not produce stats
  local a=$1
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$tmp/$a.json" nix-instantiate --eval --strict \
    --argstr arm "$a" --arg n 1 --argstr shape chain ./ci/bench/cost-classes.nix \
    >/dev/null 2>"$tmp/$a.err" || return 1
  [ -f "$tmp/$a.json" ] || return 1
  jq -r '"\(.list.elements) \(.sets.elements) \(.nrLookups)"' "$tmp/$a.json"
}

declare -A obs
for pair in "sentinel:sentinel" "peerOrder:sentinelPeerOrder" "peerClosure:sentinelPeerClosure"; do
  name=${pair%%:*}
  armName=${pair##*:}
  if ! r=$(cell "$armName"); then
    # Leave the key ABSENT rather than zero-filling: absence is what makes the classifier
    # report UNUSABLE instead of a fabricated STABLE.
    continue
  fi
  obs[$name]=$r
done

expr="{"
for name in sentinel peerOrder peerClosure; do
  [ -n "${obs[$name]+set}" ] || continue
  read -r l s k <<<"${obs[$name]}"
  expr="$expr $name = { list = $l; sets = $s; nrLookups = $k; };"
done
expr="$expr }"

nix-instantiate --eval --strict --argstr arm sentinelVerdict --arg observed "$expr" \
  --arg n 1 --argstr shape chain ./ci/bench/cost-classes.nix
