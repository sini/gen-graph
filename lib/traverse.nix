# Lazy graph traversal via accessor functions.
#
# Uses builtins.genericClosure (C-level BFS with native dedup) for
# reachability queries. ~4-5x faster than Nix-level BFS on large graphs.
#
# PER-VISIT COST — the factor this file creates. Every operator below re-reads `edges` at
# each visit and allocates one attrset per out-edge, so a visit is O(1 + outdeg), not O(1),
# and a traversal from `s` costs
#   Θ( Σ_{u ∈ reach s} (1 + outdeg u) )
# → O(reachable) only where out-degree is BOUNDED (a chain is the witness), but Θ(n²) on a
# complete DAG. The factor shows up in the allocation counters, not just asymptotically: the
# attrsets a traversal allocates are exactly |startSet| + Σ_{u ∈ visited} outdeg u, one per
# out-edge read. Consumers state their cost in this form, never as O(reachable).
#
# A CONSUMER RUNNING THIS SUM ONCE PER NODE MULTIPLIES IT BY n, which is where a dense figure
# one class worse than the operator's own comes from — and it is why `cycles` and the per-node
# partition arm no longer run it that way. They bind the amortized dual below instead, which
# charges the out-degree factor once for the whole graph; the operators above are unchanged and
# are what a caller traversing once still wants.
#
# THE AMORTIZED DUAL IS BELOW, AND IT IS A SEPARATE PAIR OF OPERATORS RATHER THAN A CHANGE TO
# THESE. The per-visit wrapping above is loop-invariant across traversals over one graph, so a
# caller spending MANY closures on one accessor can hoist it — but the hoist buys nothing for a
# caller spending one, and costs it the whole graph's wrapping where a single traversal would
# have paid only for what it reached. The operators above therefore keep their contract (they
# never enumerate `nodes`) and the amortization is a decision the CALLER makes by binding
# `hoistEdges` once and spending the result.
#
# Pure builtins only — no dependencies, so this is a bare value (not a function).
let
  # Follow edges transitively from a start node (excludes startId).
  # C-level BFS via genericClosure. Θ( Σ_{u ∈ reach startId} (1 + outdeg u) ) — the operator
  # below re-reads `edges` at every visit, so this is O(reachable) only at bounded out-degree.
  reachableFrom =
    { edges, ... }:
    startId:
    let
      result = builtins.genericClosure {
        startSet = map (id: { key = id; }) (edges startId);
        operator = item: map (id: { key = id; }) (edges item.key);
      };
    in
    builtins.filter (id: id != startId) (map (r: r.key) result);

  # Follow edges transitively, filter results by predicate on id.
  reachableWhere =
    { edges, ... }: startId: pred: builtins.filter pred (reachableFrom { inherit edges; } startId);

  # Point query: can fromId reach toId? The operator STOPS EXPANDING AT THE TARGET, so the
  # walk is Θ( Σ_{u ∈ visited} (1 + outdeg u) ) over a visited set that is `reach fromId`
  # LESS the nodes toId strictly dominates — the same per-visit cost as reachableFrom, since
  # it is the same operator, over a smaller set of visits.
  #
  # WHY THAT PRESERVES THE ANSWER. toId still ENTERS the closure whenever it is reachable;
  # only its expansion is suppressed, and genericClosure admits an item before consulting the
  # operator on it. So the result contains toId exactly when it did before, and
  # `builtins.any (r: r.key == toId)` reads membership and nothing else. What drops out is
  # precisely the set of nodes every path to which runs through toId, and nothing reads it.
  #
  # WHAT IT BUYS AND WHERE IT BUYS NOTHING — the win is SCOPED to targets that dominate a
  # sub-closure. On a chain walked from the tail a one-hop query collapses from Θ(n) to Θ(1).
  # Where the target dominates nothing the exit removes one node's out-edges and no class: on
  # a complete digraph every node sits one hop from the source, so the query stays Θ(n²).
  # `ci/bench/canreach-exit.nix` is the pair that says which regime a graph is in, and its
  # `dense` cells are there to be read as parity rather than as a win.
  #
  # genericClosure is still strict, so what remains of the closure is materialized before
  # builtins.any scans it — the scan's own short-circuit is still not the traversal's. What
  # is avoided is the whole-graph transitive closure and the target's dominated sub-closure,
  # not the rest of the per-call one.
  #
  # ★ STRICTLY MORE DEFINED THAN A FULL WALK, AND NEVER DIFFERENTLY VALUED. An accessor that
  # throws for toId's out-edges is never asked for them once toId is reached, so this answers
  # where a full walk propagates the throw. It never returns the other boolean.
  canReach =
    { edges, ... }:
    fromId: toId:
    builtins.any (r: r.key == toId) (
      builtins.genericClosure {
        startSet = map (id: { key = id; }) (edges fromId);
        operator = item: if item.key == toId then [ ] else map (id: { key = id; }) (edges item.key);
      }
    );

  # Is a node reachable from itself? (cycle detection for one node)
  # genericClosure naturally includes the start if it's in a cycle.
  selfReachable =
    { edges, ... }:
    id:
    builtins.any (r: r.key == id) (
      builtins.genericClosure {
        startSet = map (t: { key = t; }) (edges id);
        operator = item: map (t: { key = t; }) (edges item.key);
      }
    );

  # Walk parent chain upward (with cycle protection).
  # Silently terminates on cyclic parent chains.
  ancestorsOf =
    { parent, ... }:
    startId:
    let
      go =
        visited: id:
        let
          p = parent id;
        in
        if p == null then
          [ ]
        else if visited ? ${p} then
          [ ]
        else
          [ p ] ++ go (visited // { ${p} = true; }) p;
    in
    go { ${startId} = true; } startId;

  # All acyclic paths between two nodes (DFS with visited set).
  pathsBetween =
    { edges, ... }:
    startId: endId:
    let
      dfs =
        visited: current:
        if current == endId then
          [ [ endId ] ]
        else if visited ? ${current} then
          [ ]
        else
          let
            newVisited = visited // {
              ${current} = true;
            };
            targets = edges current;
          in
          builtins.concatMap (next: map (path: [ current ] ++ path) (dfs newVisited next)) targets;
    in
    dfs { } startId;

  # ── THE AMORTIZED DUAL: WRAP ONCE, TRAVERSE MANY ──
  #
  # `hoistEdges` reads the accessor over `nodes` ONCE and keeps each node's successors already
  # in `genericClosure`'s item shape, so a visit READS a list the caller built rather than
  # allocating one. It returns the successor function itself, not the map, because the map's
  # key set is not the set of ids a traversal may expand: an id outside `nodes` falls back to
  # the accessor, so the reachable set is a function of `edges` exactly as it is above and the
  # wrapping cannot silently truncate a walk that leaves the enumerated node set.
  #
  # ★ EAGER IN THE NODE SET, LAZY IN EACH NODE'S EDGES. `builtins.listToAttrs` does not force
  # its values, so what is built up front is a Θ(n) SPINE of unforced thunks; a node's `edges`
  # call, and the wrapping of its successors, happen on FIRST LOOKUP. A traversal therefore
  # never reads the edges of a node it does not visit, hoisted or not — which is measurable: an
  # accessor that throws for `b` throws when `succ "b"` is forced (so the instrument fires) and
  # does not throw when only `succ "a"` is read.
  #
  # THE COST IT MOVES, and it is a move rather than a saving. Unhoisted, a traversal from `s`
  # allocates |startSet| + Σ_{u ∈ reach s} outdeg u attrsets — one per out-edge read, at every
  # VISIT. Hoisted, a node's out-edges are wrapped once, on first lookup, however many visits
  # follow. So k traversals over one accessor go from Θ(k · Σ (1 + outdeg)) to
  # Θ(n) + Θ(Σ_{u looked up} (1 + outdeg u)) + Θ(k · |reach|) on the attrset axis: a factor of k
  # removed where k is the number of closures, which is why this is worth naming at a caller
  # that runs one per node and worth nothing at a caller that runs one per call.
  #
  # ★ AND IT IS STRICTLY WORSE FOR A SINGLE CLOSURE, though the reason is the SPINE rather than
  # the edges. A caller making exactly one closure per accessor builds the whole Θ(n) spine and
  # gets no second traversal to spread it over, while the per-node wrapping it does pay is
  # wrapping the walk would have paid anyway. The penalty is therefore a per-NODE constant, flat
  # in n and independent of E — measured at 2 to 3 attrsets per node on every shape, exactly
  # 3n + 1 on `chain`/`fleet`, 3n on `cycle` and 2n + 2 on `complete`, where nothing is unreached
  # at all. So such a caller binds the operators above
  # instead: `dependentsOf` (`lib/global.nix`) is that caller and says so at its own definition.
  hoistEdges =
    { edges, nodes, ... }:
    let
      wrap = id: map (t: { key = t; }) (edges id);
      wrapped = builtins.listToAttrs (
        map (id: {
          name = id;
          value = wrap id;
        }) nodes
      );
    in
    id: wrapped.${id} or (wrap id);

  # `succ` is a hoisted successor function — `hoistEdges accessor`, or that composed with a
  # per-round restriction, which is how a caller whose accessor narrows between traversals
  # still hoists the part that does not (`lib/partition.nix`, the worklist arm).
  closureVia =
    succ: startId:
    builtins.genericClosure {
      startSet = succ startId;
      operator = item: succ item.key;
    };

  # The hoisted readings of `reachableFrom` and `selfReachable`: same closure, same exclusion
  # of the start, same self-reappearance test, with the wrapping lifted out of the operator.
  reachableVia =
    succ: startId: builtins.filter (id: id != startId) (map (r: r.key) (closureVia succ startId));

  selfReachableVia = succ: id: builtins.any (r: r.key == id) (closureVia succ id);
in
{
  inherit
    reachableFrom
    reachableWhere
    canReach
    selfReachable
    ancestorsOf
    pathsBetween
    hoistEdges
    reachableVia
    selfReachableVia
    ;
}
