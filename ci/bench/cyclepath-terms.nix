# Allocation benchmark for two overlapping cost classes:
#
#   1. the two terms `topoOrder`'s CYCLE PATH pays — a `global.cycles` call and a
#      `global.condensation` call (`lib/order.nix`, the `ok = false` branch);
#   2. the `fp.transitiveClosure`-INHERITING class — every surface whose cost is a
#      closure call: `dependents` (`global.nix`), `condensation` (twice: the graph
#      closure and the quotient closure), and `transitiveReduction` (`fixpoint.nix`).
#      These share one cost and must be documented from one measurement, or a reader
#      comparing two rows infers a distinction that does not exist.
#
# WHY THIS EXISTS: the cycle path's cost comment once named a single dominant
# term. It cannot. Which of the two terms is larger flips with the graph shape
# AND with the allocation axis, so any comparative claim about them has to be
# measured on both shapes and all three axes rather than argued.
#
# ★ THE COUNTERS ARE A LOWER BOUND. `list.elements`/`sets.elements`/`nrLookups`
# count Nix-heap allocation only. `genericClosure` keeps its done-set in C++, so its
# key comparisons appear in NONE of the three axes. Every figure here is a floor on
# the real cost, not the bill; state that limit rather than closing it with a number.
#
# INTERFACE — `arm` × `shape` × `n`:
#   arm   = cycles | condensation | dependents | transitiveClosure
#         | transitiveReduction | floor
#   shape = complete | cycle
#   n     = node count (use doublings, e.g. 50/100/200, so a ratio reads as 2^exp)
#
# FIXTURES, and why these two:
#   `complete` — the complete digraph: every node points at every other. Out-degree
#     is n-1 (UNBOUNDED) and the whole graph is ONE SCC, so the cycle path really
#     runs. This is the shape a "dense" claim quantifies over.
#   `cycle` — the simple cycle: out-degree 1 (BOUNDED), one SCC, diameter n.
#     The bounded-out-degree counterpart, and the shape that shows the ordering
#     between the two terms is not fixed.
#   Both are CYCLIC by construction: a complete DAG is acyclic and orders
#   successfully, so it never reaches the cycle path at all and cannot be used
#   to price it.
#   `floor` deep-forces the caller's edge set alone — the fixture's own cost,
#   containing no gen-graph work — so a library figure can be read against it.
#
# The `condensation` arm forces `.sccs`. `lib/order.nix` instead applies `.sccOf`
# to every cyclic key, which forces the same transitive closure, so this arm's
# cost class is the one the cycle path actually pays.
#
# RUN (all three axes; a single-axis read is what this file exists to prevent):
#   NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/s.json nix-instantiate --eval --strict \
#     --arg n 200 --argstr arm condensation --argstr shape cycle ./ci/bench/cyclepath-terms.nix
#   nix-instantiate --eval --raw -E 'let s = builtins.fromJSON (builtins.readFile "/tmp/s.json"); in
#     "${toString s.list.elements} ${toString s.sets.elements} ${toString s.nrLookups}"'
{
  n ? 50,
  arm ? "cycles",
  shape ? "complete",
}:
let
  g = import ../../default.nix { };

  # zero-padded so ids sort lexicographically in index order
  pad =
    i:
    let
      s = toString i;
      z = builtins.substring 0 (5 - builtins.stringLength s) "00000";
    in
    "n${z}${s}";
  nodes = builtins.genList pad n;
  idxOf = builtins.listToAttrs (
    builtins.genList (i: {
      name = pad i;
      value = i;
    }) n
  );

  completeEdges = id: builtins.filter (x: x != id) nodes;
  cycleEdges =
    id:
    let
      i = idxOf.${id};
    in
    [ (pad (if i + 1 < n then i + 1 else 0)) ];

  # An unknown SHAPE must refuse exactly as loudly as an unknown ARM. Falling through
  # to a default fixture would tag a real figure with a shape that was never measured.
  edges =
    if shape == "complete" then
      completeEdges
    else if shape == "cycle" then
      cycleEdges
    else
      throw "unknown shape ${shape}";
  acc = { inherit nodes edges; };

  result =
    if arm == "cycles" then
      g.cycles acc
    else if arm == "condensation" then
      (g.condensation acc).sccs
    # `dependents` is curried (accessor -> targetId) and computes the FULL closure
    # before filtering, so the closure cost is paid whichever target is named.
    else if arm == "dependents" then
      g.dependents acc (builtins.head nodes)
    else if arm == "transitiveClosure" then
      g.transitiveClosure acc
    else if arm == "transitiveReduction" then
      g.transitiveReduction acc
    else if arm == "floor" then
      builtins.deepSeq (map edges nodes) nodes
    else
      throw "unknown arm ${arm}";
in
builtins.deepSeq result {
  inherit arm shape n;
  # SHAPE CONTROL, read on every run: both fixtures must be ONE SCC, or the arm is
  # not measuring the cycle path's regime. `cycles` ⇒ len n, `condensation` ⇒ len 1.
  # `transitiveClosure` ⇒ len n. `dependents` ⇒ len n-1 (target filtered out).
  # `transitiveReduction` ⇒ len 0 on `complete`: every edge is implied by a two-hop
  # path, and `differenceEdges` drops a key whose row empties — producing that answer
  # still forces the closure, which is the cost being measured.
  len =
    if builtins.isList result then
      builtins.length result
    else
      builtins.length (builtins.attrNames result);
}
