#!/usr/bin/env bash
# Reads the `canreach-exit.nix` pairing and prints one row per cell, all three axes.
#
# Both columns are read in ONE invocation of this script, on one revision of the bench file,
# because the comparison is between two constructions and not between two runs. The `answer`
# column is printed beside the counters rather than checked here: an early exit that changes
# an answer is a wrong answer, and that judgement belongs to the reader of the table, not to
# a transport script that could silently drop a row.
#
#   ./ci/bench/canreach-exit.sh [n]        -> arm shape cell answer list sets nrLookups
#
# A cell that fails to produce stats prints FAILED and does not print zeros: a cell that did
# not run must never be reported as a cell that allocated nothing.
set -u
cd "$(dirname "$0")/../.." || exit 99
n=${1:-1000}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '%-8s %-6s %-5s %-6s %12s %10s %12s\n' arm shape cell answer list sets nrLookups
for shape in chain dense; do
  for arm in floor shipped live; do
    for cell in near far miss; do
      [ "$arm" = floor ] && [ "$cell" != near ] && continue
      f="$tmp/$shape-$arm-$cell.json"
      out=$(NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$f" nix-instantiate --eval --strict \
        --arg n "$n" --argstr arm "$arm" --argstr shape "$shape" --argstr cell "$cell" \
        ./ci/bench/canreach-exit.nix 2>"$tmp/err") || {
        printf '%-8s %-6s %-5s %-6s %12s %10s %12s\n' "$arm" "$shape" "$cell" FAILED - - -
        continue
      }
      ans=$(sed -n 's/.*answer = \([a-z]*\);.*/\1/p' <<<"$out")
      read -r l s k < <(jq -r '"\(.list.elements) \(.sets.elements) \(.nrLookups)"' "$f")
      label=$cell
      [ "$arm" = floor ] && label='-'
      printf '%-8s %-6s %-5s %-6s %12s %10s %12s\n' \
        "$arm" "$shape" "$label" "$ans" "$l" "$s" "$k"
    done
  done
done
