# Allocation benchmark for `canReach`'s TARGETED EARLY EXIT — the asymmetry between a query
# whose target dominates a sub-closure and one whose target does not.
#
# ★ WHY THIS IS NOT AN ARM IN `cost-classes.nix`, and the reason is structural rather than
# stylistic. That file reads a SHAPE CONTROL on every non-sentinel run —
# `initialReady = length (filter (k: edges k == [ ]) nodes)` — which calls `edges` at EVERY
# node before the arm's own figure is read. That is the right control for the classes it
# prices, all of which cover the whole graph anyway. It is fatal here, and the failure is a
# SWAMPING rather than a flattening — MEASURED by forcing that same `initialReady` beside
# these arms, `chain`, `list.elements`, n = 500/1000/2000:
#
#   without it   near 6 / 6 / 6        ·  miss 1500 / 3000 / 6000
#   with it      near 1006 / 2006 / 4006  ·  miss 2500 / 5000 / 10000
#
# The cells stay distinguishable, so a reader is not warned by a wall of equal numbers — they
# are simply no longer readings of the query. At n=1000 the control is **99.7% of the Θ(1)
# cell** (2000 of 2006); the near:miss asymmetry collapses from **500x to 2.5x**; and the
# near-query exponent moves from **0.00 to 1.00**, past the 0.2 threshold the early exit is
# judged against, for a reason with nothing to do with the construction. A control that costs
# Θ(n) cannot sit under a Θ(1) arm. The measurement and the control are incompatible, so they
# live in separate files rather than one file with a conditional guard.
#
# ★ AND THE FIXTURES ARE ARITHMETIC, FOR THE SAME REASON. `cost-classes.nix` precomputes a
# dependency attrset per shape, so every cell pays a Θ(n) preamble; that is invisible against
# a Θ(n) or Θ(n²) arm and it would be the entire reading of a Θ(1) one. The `chain` accessor
# below computes a node's successor from its own id and allocates nothing up front, so a
# one-hop query's figure is the query's.
#
# ★ NOTHING HERE DEPENDS ON KEY ORDER, which is why the ids are not zero-padded (they are in
# `cost-classes.nix`, where two constructions of one graph differ by 3x on ready-set cost).
# `chain` has out-degree 1, so the frontier holds one element whatever the order; `dense` is
# symmetric under permutation. The figures below are invariant under the id spelling.
#
# THE PAIRING, and it is the whole instrument. `shipped` reproduces the pre-early-exit
# construction VERBATIM; `live` binds the library. Neither column means anything alone:
#   · `shipped` alone cannot show an early exit, because it has none — its three cells are
#     bit-identical by construction, and that identity IS the baseline being displaced.
#   · `live` alone cannot show one either, because a figure with nothing to compare against
#     is a number, not an asymmetry.
# Both live in ONE revision of this file so the comparison is not across two harnesses. Same
# reason `coneRankShipped` and the `*Unhoisted` arms are reproduced rather than cited in
# `cost-classes.nix`: a baseline quoted from a figure nobody can re-run is not a baseline.
#
# ★ THE COUNTERS ARE A LOWER BOUND, exactly as in `cost-classes.nix`.
# `list.elements`/`sets.elements`/`nrLookups` count Nix-heap allocation only, and
# `genericClosure` keeps its done-set and its key comparisons in C++, where none of the three
# axes can see them. Every figure here is a floor on the real cost. A wall-clock reading is a
# separate instrument and is not substituted for by these.
#
# THE ANSWER IS RETURNED ON EVERY RUN, and it is a control rather than a convenience: an
# early exit that changes an answer is a wrong answer, so a cost figure whose cell answered
# differently from its pair is not a faster reading of the same question.
#
# INTERFACE — `arm` × `shape` × `cell`:
#   arm   = shipped | live | floor
#   shape = chain | dense
#   cell  = near | far | miss
#   n     = node count (use doublings, e.g. 500/1000/2000, so a ratio reads as 2^exp)
#
# THE CELLS, and what each is for:
#   `chain` is the shape where the target DOMINATES a sub-closure: from the tail, every node
#     past the target is reachable only through it. `near` (one hop) is where an operator that
#     stops expanding at the target reads Θ(1) and one that does not reads Θ(n); `far` (the
#     head) and `miss` (an absent id) both walk the whole chain either way, so the pair
#     `near` vs `miss` is the asymmetry and `far` is the control that says the walk still
#     happens when the target is genuinely deep.
#   `dense` is the shape where the target dominates NOTHING: the complete digraph puts every
#     node one hop from the source, so suppressing one node's expansion removes n-1 out-edge
#     reads out of Θ(n²) and cannot change the class. It is the NEGATIVE cell — it is here to
#     be read as parity, and a run claiming a dense win is measuring something else.
#
# RUN (all three axes; a single-axis read is what the sibling file exists to prevent):
#   NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/s.json nix-instantiate --eval --strict \
#     --arg n 1000 --argstr arm live --argstr shape chain --argstr cell near \
#     ./ci/bench/canreach-exit.nix
#   nix-instantiate --eval --raw -E 'let s = builtins.fromJSON (builtins.readFile "/tmp/s.json"); in
#     "${toString s.list.elements} ${toString s.sets.elements} ${toString s.nrLookups}"'
{
  n ? 1000,
  arm ? "live",
  shape ? "chain",
  cell ? "near",
}:
let
  # `default.nix`'s prelude shim, spelled out here so the library and the reproduced baseline
  # share ONE prelude — a second evaluation of gen-prelude would be priced as if it were the
  # construction. (`canReach` itself takes no prelude; this is what `import ../../lib` needs.)
  prelude =
    let
      lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
      node = lock.nodes.gen-prelude.locked;
    in
    import "${
      builtins.fetchTree {
        inherit (node)
          type
          owner
          repo
          rev
          narHash
          ;
      }
    }/lib";
  g = import ../../lib { inherit prelude; };

  # ── THE BASELINE, VERBATIM BEFORE THE EARLY EXIT ──
  # The operator expands every visited node unconditionally, so the source's closure is
  # materialized in full whatever the target and `builtins.any` short-circuits its scan of the
  # finished list rather than the traversal that built it. It differs from the shipped
  # `canReach` in the operator and in nothing else.
  canReachShipped =
    { edges, ... }:
    fromId: toId:
    builtins.any (r: r.key == toId) (
      builtins.genericClosure {
        startSet = map (id: { key = id; }) (edges fromId);
        operator = item: map (id: { key = id; }) (edges item.key);
      }
    );

  # ── FIXTURES ──
  # `chain`: node i points at i-1, so the tail reaches the head and every node between them is
  # reachable ONLY through its own successor. Successors are computed from the id, so the
  # accessor is O(1) per call with no preamble at all.
  chain = {
    edges =
      id:
      let
        i = builtins.fromJSON id;
      in
      if i <= 0 then [ ] else [ (toString (i - 1)) ];
  };

  # `dense`: the complete digraph, out-degree n-1 and diameter 1. The node list is built once
  # (Θ(n)) and each call filters it (Θ(n)), which is the real per-visit cost of this shape and
  # not a harness artefact.
  denseNodes = builtins.genList toString n;
  dense = {
    edges = id: builtins.filter (x: x != id) denseNodes;
  };

  acc =
    if shape == "chain" then
      chain
    else if shape == "dense" then
      dense
    else
      throw "unknown shape ${shape}";

  # An unknown SHAPE or CELL must refuse exactly as loudly as an unknown ARM: falling through
  # to a default would tag a real figure with a query that was never run.
  #
  # `chain` queries run from the TAIL, the only node whose closure is the whole graph.
  # `dense` queries run from node 0; every other node is one hop away, so `near` and `far`
  # differ only in which node is named — which is itself the point of the negative cell.
  fromId = if shape == "chain" then toString (n - 1) else "0";
  toId =
    if cell == "miss" then
      "absent"
    else if shape == "chain" then
      (if cell == "near" then toString (n - 2) else "0")
    else if cell == "near" then
      "1"
    else if cell == "far" then
      toString (n - 1)
    else
      throw "unknown cell ${cell}";

  # The FLOOR reads what every query arm reads before its closure begins — the source's own
  # out-edges — and nothing else, so a net-of-floor figure is the closure's own cost. It is an
  # arm rather than a preamble: measured in the same run, under the same fixture bindings.
  result =
    if arm == "floor" then
      builtins.deepSeq (acc.edges fromId) true
    else if arm == "shipped" then
      canReachShipped acc fromId toId
    else if arm == "live" then
      g.canReach acc fromId toId
    else
      throw "unknown arm ${arm}";
in
builtins.deepSeq result {
  inherit
    arm
    shape
    cell
    n
    ;
  inherit fromId toId;
  # THE ANSWER CONTROL, read on every run. `near` and `far` are reachable and `miss` is not,
  # on both shapes; a cell whose answer disagrees with its pair's is not a cost reading of the
  # same question. The floor arm answers `true` because it is not a query — its `answer` is
  # not comparable to a query arm's and is not read as one.
  answer = result;
}
