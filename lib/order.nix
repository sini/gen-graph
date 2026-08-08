# Ordering — the one ordering front door for the gen ecosystem, plus the
# home-manager-style DAG entry constructors (before/after) layered on top of it.
#
# THEORY: `topoOrder` is A. B. Kahn's algorithm (1962, "Topological sorting of large
# networks", CACM 5(11)) — indegree over the dependency relation, a ready set of
# indegree-zero nodes, and the residual-emptiness check for cycles. This is A. B. Kahn
# 1962, NOT Gilles Kahn 1974 (KPN, cited in preorder.nix for the lazy accessor pattern):
# a different author and a different result. `entry*`/`phaseOrder` are the home-manager
# dag idiom (generalized strings-with-deps) expressed over it, absorbing what
# gen-dispatch's dag.nix used to own so gen-dispatch can be the pure dispatch STEP.
#
# EDGE DIRECTION, stated once and shared by every surface in this library:
# `edges u ∋ v` means "u DEPENDS ON v" (consumer → producer). An ordering is therefore
# producers-first: a node is emitted only after everything it depends on. `coneRank`,
# `condensation.bottomUp`, `dependentsOf` and `reachableFrom` all read the accessor this
# way, and callers that build their own accessor (gen-vars) do too.
#
# COST: building the reverse index and the indegree map is O(n + E) via groupBy; the loop
# performs exactly E decrements. The residual is min-extraction over the ready set, which
# a priority queue would make O(log n) and which pure Nix cannot express — there is no
# mutable heap in the substrate, the same bound that keeps `condensation` off Tarjan. The
# ready set is held sorted and consumed by cursor, so a re-sort costs only when a node
# becomes ready, and a graph whose ready set stays small (any chain) runs in O(n + E).
# The CYCLE path is deliberately not derived from the Kahn residual — a residual knows
# only THAT nodes went unemitted, not which cycles they form — so it costs a `global.cycles`
# call PLUS `global.condensation`, and it runs only on a CYCLIC graph. NEITHER term may be
# quoted as the cost alone: which of the two is larger flips with the graph shape and with
# the allocation axis measured. Ordering succeeds or it throws; the expensive analysis is on
# the way out.
{ prelude }:
let
  global = import ./global.nix { inherit prelude; };

  entryBetween = before: after: { inherit before after; };
  entryAnywhere = entryBetween [ ] [ ];
  entryAfter = after: entryBetween [ ] after;
  entryBefore = before: entryBetween before [ ];

  # topoOrder { nodes; edges; keyOf ? id; lessThan ? builtins.lessThan }
  #   => { ok = true; order = [ node ]; } | { ok = false; cycles = [ [ node ] ]; }
  #
  # NON-THROWING on a cycle: both migrating consumers build their own diagnostic from the
  # cycle set (gen-pipe names the channels and the operators; gen-edge names the
  # (target, channel) chain), so a front door that throws first denies them the material.
  # `phaseOrder` below is the throwing convenience layer for callers that want one.
  #
  # `keyOf` projects a node to its STRING identity, which is also its tie-break key. It
  # admits node values that are not themselves strings — gen-edge orders edge RECORDS by
  # a canonical sort key — and it is what makes the tie-break caller-supplied: ordering
  # incomparable nodes by a frozen key is what makes an ordering a pure function of the
  # node SET rather than of the input permutation. `lessThan` orders those keys, so a
  # caller wanting a different tie-break over the same identities supplies it there.
  #
  # A `keyOf` output that is not a string, two nodes sharing a key, and an edge naming a
  # node outside `nodes` are all REFUSALS BY NAME. Each would otherwise reach `genAttrs`
  # or the indegree map and either abort with a type error that `tryEval` cannot catch,
  # or — worse — silently merge two nodes / report a phantom cycle.
  topoOrder =
    {
      nodes,
      edges,
      keyOf ? (node: node),
      lessThan ? builtins.lessThan,
    }:
    let
      keyed = prelude.imap0 (i: node: {
        inherit i node;
        key = keyOf node;
      }) nodes;
      keys = map (k: k.key) keyed;

      # ── refusals, in the order that makes each one's own check safe to run ──
      # `builtins.isString` first: every later check indexes an attrset by the key, and a
      # non-string attribute name is the uncatchable abort this whole guard exists for.
      nonString = builtins.filter (k: !builtins.isString k.key) keyed;
      keySet = prelude.genAttrs keys (_: true);
      byKey = builtins.groupBy (k: k.key) keyed;
      collisions = builtins.filter (g: builtins.length g > 1) (prelude.mapAttrsToList (_: g: g) byKey);
      nodeOf = prelude.mapAttrs (_: g: (builtins.head g).node) byKey;
      rawDepsOf = prelude.genAttrs keys (k: map keyOf (edges nodeOf.${k}));
      dangling = builtins.filter (d: !(builtins.isString d) || !(keySet ? ${d})) (
        prelude.concatMap (k: rawDepsOf.${k}) keys
      );

      refusal =
        if nonString != [ ] then
          let
            bad = builtins.head nonString;
          in
          "keyOf returned a non-string key (type ${builtins.typeOf bad.key}) for the node at "
          + "index ${toString bad.i}; ordering keys must be strings"
        else if collisions != [ ] then
          let
            g = builtins.head collisions;
          in
          "key ${builtins.toJSON (builtins.head g).key} names ${toString (builtins.length g)} nodes "
          + "(indices ${builtins.toJSON (map (k: k.i) g)}); ordering keys must be unique"
        else if dangling != [ ] then
          let
            d = builtins.head dangling;
          in
          "edge target ${
            if builtins.isString d then builtins.toJSON d else "of type ${builtins.typeOf d}"
          } is not in nodes"
        else
          null;

      # ── Kahn 1962 ──
      # An edge SET, so a repeated dependency counts once: `genAttrs` collapses duplicate
      # names, and an indegree that counts an arc the decrement only pays once would
      # never reach zero.
      depsOf = prelude.mapAttrs (_: ds: builtins.attrNames (prelude.genAttrs ds (_: true))) rawDepsOf;
      # Reverse index — the pick's successors, the only indegrees a pick may touch. O(E).
      dependentsOf = prelude.mapAttrs (_: es: map (e: e.value) es) (
        builtins.groupBy (e: e.name) (
          prelude.concatMap (
            k:
            map (d: {
              name = d;
              value = k;
            }) depsOf.${k}
          ) keys
        )
      );

      sortKeys = builtins.sort lessThan;
      indeg0 = prelude.mapAttrs (_: ds: builtins.length ds) depsOf;

      # The ready set is a sorted array walked by cursor: while nothing new becomes ready
      # the pick is a pointer bump, and a re-sort is paid only for the nodes that actually
      # arrive. Re-sorting the whole residue on every pick is what makes the shipped
      # gen-edge loop cubic.
      step =
        st:
        if st.cursor >= builtins.length st.ready then
          st
        else
          let
            pick = builtins.elemAt st.ready st.cursor;
            succs = dependentsOf.${pick} or [ ];
            indeg = st.indeg // prelude.genAttrs succs (s: st.indeg.${s} - 1);
            newly = builtins.filter (s: indeg.${s} == 0) succs;
            residue = builtins.genList (i: builtins.elemAt st.ready (st.cursor + 1 + i)) (
              builtins.length st.ready - st.cursor - 1
            );
          in
          step {
            inherit indeg;
            ready = if newly == [ ] then st.ready else sortKeys (residue ++ newly);
            cursor = if newly == [ ] then st.cursor + 1 else 0;
            emitted = st.emitted ++ [ pick ];
          };

      final = step {
        indeg = indeg0;
        ready = sortKeys (builtins.filter (k: indeg0.${k} == 0) keys);
        cursor = 0;
        emitted = [ ];
      };

      # The cycle report is SCC MEMBERSHIP, named by `cycles`/`condensation` rather than
      # read off the residual: every node in a cycle, grouped by its component, sorted
      # within each group. `cycles` is self-reachability, so a self-loop is reported as
      # the singleton it is — a component `condensation` alone cannot distinguish from an
      # acyclic node.
      keyAccessor = {
        nodes = keys;
        edges = k: depsOf.${k} or [ ];
      };
      cyclicKeys = global.cycles keyAccessor;
      sccOf = (global.condensation keyAccessor).sccOf;
      cycles = prelude.mapAttrsToList (_: g: map (k: nodeOf.${k}) g) (builtins.groupBy sccOf cyclicKeys);
    in
    if refusal != null then
      throw "gen-graph.topoOrder: ${refusal}"
    else if builtins.length final.emitted < builtins.length keys then
      {
        ok = false;
        inherit cycles;
      }
    else
      {
        ok = true;
        order = map (k: nodeOf.${k}) final.emitted;
      };

  # after=[d] on n => n depends on d (edge n->d); before=[t] on n => t depends on n
  # (edge t->n). Both readings are the library direction stated in the header, so the
  # order comes straight off the front door with nothing to compensate for.
  phaseOrder =
    entries:
    let
      names = builtins.attrNames entries;
      arcs = prelude.concatMap (
        n:
        map (d: {
          from = n;
          to = d;
        }) (entries.${n}.after or [ ])
        ++ map (t: {
          from = t;
          to = n;
        }) (entries.${n}.before or [ ])
      ) names;
      grouped = builtins.groupBy (x: x.from) arcs;
      result = topoOrder {
        nodes = names;
        edges = id: map (x: x.to) (grouped.${id} or [ ]);
      };
    in
    # Throw-on-cycle preserves the contract gen-dispatch's dag.nix had.
    if result.ok then
      result.order
    else
      throw "gen-graph.phaseOrder: cyclic ordering constraints: ${builtins.toJSON result.cycles}";
in
{
  inherit
    entryAnywhere
    entryAfter
    entryBefore
    entryBetween
    topoOrder
    phaseOrder
    ;
}
