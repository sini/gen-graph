# Allocation benchmark for the two terms `topoOrder`'s CYCLE PATH pays: a
# `global.cycles` call and a `global.condensation` call (`lib/order.nix`, the
# `ok = false` branch).
#
# WHY THIS EXISTS: the cycle path's cost comment once named a single dominant
# term. It cannot. Which of the two terms is larger flips with the graph shape
# AND with the allocation axis, so any comparative claim about them has to be
# measured on both shapes and all three axes rather than argued.
#
# INTERFACE — `arm` × `shape` × `n`:
#   arm   = cycles | condensation | floor
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

  edges = if shape == "complete" then completeEdges else cycleEdges;
  acc = { inherit nodes edges; };

  result =
    if arm == "cycles" then
      g.cycles acc
    else if arm == "condensation" then
      (g.condensation acc).sccs
    else if arm == "floor" then
      builtins.deepSeq (map edges nodes) nodes
    else
      throw "unknown arm ${arm}";
in
builtins.deepSeq result {
  inherit arm shape n;
  # SHAPE CONTROL, read on every run: both fixtures must be ONE SCC, or the arm is
  # not measuring the cycle path's regime. `cycles` ⇒ len n, `condensation` ⇒ len 1.
  len = builtins.length result;
}
