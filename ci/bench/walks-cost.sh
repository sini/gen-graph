#!/usr/bin/env bash
# The reachability walks' COST ORACLE: `expandPreorder`, `foldReach`, `foldPreorder` and
# `ancestorsOf` over a chain, read under NIX_SHOW_STATS on three meters —
# `nrFunctionCalls`, `nrOpUpdateValuesCopied` and `list.elements`.
#
#   ./ci/bench/walks-cost.sh     -> one row per (arm, n), then LINEARITHMIC | QUADRATIC | INVALID
#
# THE BOUND IS OVER A SPAN, NOT PER DOUBLING. The copies are Θ(n log(n/32)) (`lib/preorder.nix`'s
# header), whose per-doubling ratio is not constant — it falls toward 2 as n grows — and whose
# carry cascades are amortised, so a single doubling can read high. The verdict is the geometric
# mean ratio per doubling over 1,000 → 8,000, i.e. (v(8000) / v(1000))^(1/3), against 2.6 on
# every meter: a linear or linearithmic walk reads ≈2.0–2.3, the quadratic walk it replaced read
# ≈4.0. The intermediate points are printed for the reader and not gated.
#
# TWO CONTROLS, BOTH GATING. `materializeParents` must read FLAT on copies (the instrument adds
# no per-n copies of its own) and `quadraticVisited`, the old per-step `//` visited set, must read
# ≥ 3.5 per doubling on copies (the instrument can see a quadratic). Either failing is INVALID,
# never a pass. So is a cell that produced no stats or the wrong answer: a cell that did not
# run must never be read as a cell that allocated nothing.
set -u
cd "$(dirname "$0")/../.." || exit 99
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sizes=(1000 2000 4000 8000)
lo=1000
hi=8000
bound=2.6
invalid=0
over=0

declare -A reading
cell() { # cell <arm> <n> -> sets reading[arm,n] to "calls copies listel", or returns 1
  local f="$tmp/$1-$2.json" out want
  out=$(NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$f" nix-instantiate --eval --strict \
    --argstr arm "$1" --arg n "$2" ./ci/bench/walks-cost.nix 2>"$tmp/err") || {
    echo "  FAILED: $(grep -o 'error: .*' "$tmp/err" | tail -1)"
    return 1
  }
  want=$2
  case "$1" in ancestorsOf | materializeParents) want=$(($2 - 1)) ;; esac
  [ "$out" = "$want" ] || {
    echo "  WRONG ANSWER: length $out, wanted $want"
    return 1
  }
  [ -s "$f" ] || {
    echo "  NO STATS"
    return 1
  }
  reading[$1,$2]=$(jq -r '"\(.nrFunctionCalls) \(.nrOpUpdateValuesCopied) \(.list.elements)"' "$f") || return 1
}

ratio() { # ratio <v(lo)> <v(hi)> -> geometric mean per doubling over the span
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", (b / a) ^ (1 / 3) }'
}

printf '%-20s %6s %10s %10s %10s\n' arm n calls copies list.el
for arm in expandPreorder foldReach foldPreorder ancestorsOf materializeParents quadraticVisited; do
  for n in "${sizes[@]}"; do
    if cell "$arm" "$n"; then
      read -r c u l <<<"${reading[$arm,$n]}"
      printf '%-20s %6s %10s %10s %10s\n' "$arm" "$n" "$c" "$u" "$l"
    else
      printf '%-20s %6s   (above: this cell could not be measured)\n' "$arm" "$n"
      invalid=1
    fi
  done
done
[ "$invalid" -eq 0 ] || {
  echo "INVALID (a cell could not be measured)"
  exit 2
}

echo
printf '%-20s %10s %10s %10s   (per doubling, %s -> %s)\n' arm calls copies list.el "$lo" "$hi"
for arm in expandPreorder foldReach foldPreorder ancestorsOf materializeParents quadraticVisited; do
  read -r c0 u0 l0 <<<"${reading[$arm,$lo]}"
  read -r c1 u1 l1 <<<"${reading[$arm,$hi]}"
  rc=$(ratio "$c0" "$c1")
  ru=$(ratio "$u0" "$u1")
  rl=$(ratio "$l0" "$l1")
  printf '%-20s %10s %10s %10s\n' "$arm" "$rc" "$ru" "$rl"
  case "$arm" in
  materializeParents)
    [ "$u0" = "$u1" ] || {
      echo "  control did not read flat on copies ($u0 -> $u1)"
      invalid=1
    }
    ;;
  quadraticVisited)
    awk -v r="$ru" 'BEGIN { exit !(r >= 3.5) }' || {
      echo "  control did not read quadratic on copies ($ru per doubling)"
      invalid=1
    }
    ;;
  *)
    for r in "$rc" "$ru" "$rl"; do
      awk -v r="$r" -v b="$bound" 'BEGIN { exit !(r > b) }' && over=1
    done
    ;;
  esac
done

echo
if [ "$invalid" -ne 0 ]; then
  echo "INVALID (a control did not fire)"
  exit 2
elif [ "$over" -ne 0 ]; then
  echo "QUADRATIC (a walk exceeded $bound per doubling on some meter)"
  exit 1
else
  echo "LINEARITHMIC"
fi
