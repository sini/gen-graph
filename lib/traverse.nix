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
  inherit (import ./key.nix)
    attrKey
    badResult
    callableAt
    renderId
    edgesAccessor
    identifier
    nodeKey
    notEdgeList
    retiredMaxDepth
    ;
  # Follow edges transitively from a start node (excludes startId).
  # C-level BFS via genericClosure. Θ( Σ_{u ∈ reach startId} (1 + outdeg u) ) — the operator
  # below re-reads `edges` at every visit, so this is O(reachable) only at bounded out-degree.
  #
  # THE RELATION, STATED EXACTLY: `reachableFrom startId` is `R*(startId) \ { startId }`, the
  # reflexive-transitive closure less the start itself. The self-bit — whether `startId ∈
  # R*(startId)`, i.e. whether it lies on a cycle — is `selfReachable`'s alone; the two are
  # complementary projections of one closure, not disagreeing readings of it. (Tarjan 1972
  # defines descendant INCLUSIVELY — "every vertex is an ancestor and a descendant of itself"
  # — and its reachability idiom is reflexive, "zero or more arcs", so the strict set this
  # operator returns is unnamed at that primary; this library names it and hands the
  # reflexive bit to `selfReachable` by construction.)
  reachableFrom =
    { edges, ... }:
    startId:
    builtins.seq (nodeKey "reachableFrom" startId) (
      let
        e = edgesAccessor "reachableFrom" edges;
        result = builtins.genericClosure {
          startSet = map (id: { key = id; }) (
            let
              es = e startId;
            in
            if builtins.isList es then es else throw (notEdgeList "reachableFrom" startId es)
          );
          operator =
            item:
            map (id: { key = id; }) (
              let
                es = e item.key;
              in
              if builtins.isList es then es else throw (notEdgeList "reachableFrom" item.key es)
            );
        };
      in
      builtins.filter (id: id != startId) (map (r: r.key) result)
    );

  # Follow edges transitively, filter results by predicate on id.
  reachableWhere =
    { edges, ... }:
    startId: pred:
    builtins.seq (nodeKey "reachableWhere" startId) (
      let
        p = callableAt "reachableWhere" "pred" "a bool" pred;
      in
      builtins.filter (
        id:
        let
          b = p id;
        in
        if builtins.isBool b then b else badResult "reachableWhere" "pred" (renderId id) "a bool" b
      ) (reachableFrom { inherit edges; } startId)
    );

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
    builtins.seq (nodeKey "canReach" fromId) (
      builtins.seq (nodeKey "canReach" toId) (
        let
          e = edgesAccessor "canReach" edges;
        in
        builtins.any (r: r.key == toId) (
          builtins.genericClosure {
            startSet = map (id: { key = id; }) (
              let
                es = e fromId;
              in
              if builtins.isList es then es else throw (notEdgeList "canReach" fromId es)
            );
            operator =
              item:
              if item.key == toId then
                [ ]
              else
                map (id: { key = id; }) (
                  let
                    es = e item.key;
                  in
                  if builtins.isList es then es else throw (notEdgeList "canReach" item.key es)
                );
          }
        )
      )
    );

  # Is a node reachable from itself? (cycle detection for one node)
  # genericClosure naturally includes the start if it's in a cycle.
  selfReachable =
    { edges, ... }:
    id:
    builtins.seq (nodeKey "selfReachable" id) (
      let
        e = edgesAccessor "selfReachable" edges;
      in
      builtins.any (r: r.key == id) (
        builtins.genericClosure {
          startSet = map (t: { key = t; }) (
            let
              es = e id;
            in
            if builtins.isList es then es else throw (notEdgeList "selfReachable" id es)
          );
          operator =
            item:
            map (t: { key = t; }) (
              let
                es = e item.key;
              in
              if builtins.isList es then es else throw (notEdgeList "selfReachable" item.key es)
            );
        }
      )
    );

  # Walk parent chain upward (with cycle protection).
  # Silently terminates on cyclic parent chains.
  #
  # A `genericClosure` over the parent chain (den-hoag-kirr's `dependentsFrontier` construction):
  # the operator applies `parent` once and emits the one parent, so the closure's element order
  # IS the chain order, and its C-level done set is the cycle guard. It keys by `==`, which
  # ignores string context — the partition `attrKey` induces — so a context-carrying id comes
  # back with its context (the key IS the value). Θ(depth) calls, no per-step copy, and no
  # evaluator ceiling: there is no recursion, so the old depth cap and its refusal are retired
  # and `maxDepth` is refused by name (`preorder.nix`'s header, and its recorded price: an
  # infinite demand-generated parent chain of distinct ids diverges).
  ancestorsOf =
    {
      parent,
      maxDepth ? null,
      ...
    }:
    if maxDepth != null then
      throw (retiredMaxDepth "ancestorsOf")
    else
      startId:
      let
        pa = callableAt "ancestorsOf" "parent" "a node id (a string) or null" parent;
        chain = builtins.genericClosure {
          startSet = [ { key = startId; } ];
          operator =
            x:
            let
              p = pa x.key;
            in
            if p == null then
              [ ]
            else if !builtins.isString p then
              badResult "ancestorsOf" "parent" (renderId x.key) "a node id (a string) or null" p
            else
              [ { key = p; } ];
        };
      in
      builtins.seq (identifier "ancestorsOf" startId) (map (x: x.key) (builtins.tail chain));

  # All acyclic paths between two nodes (DFS with visited set).
  #
  # ── ITS DEPTH CEILING, NAMED RATHER THAN REMOVED ──
  #
  # `dfs` is SELF-RECURSIVE, so the evaluator's call depth is the length of the path being
  # extended, and past the evaluator's own `max-call-depth` the failure is `stack overflow;
  # max-call-depth exceeded` — an ABORT, not a throw, invisible to `builtins.tryEval`.
  # Measured on a bare chain probe at `374b0ad`: returns at 2,497, aborts at 2,498, ≈4
  # evaluator frames per link against the 10,000 default. DEPTH-driven and not n-driven —
  # `star` at 16,000 nodes and depth 1 returns.
  #
  # ★ THE BOUNDARY IS A PROPERTY OF THE WHOLE MEASURING EXPRESSION, not of this surface, so
  # no figure quoted here is a ceiling a CALLER inherits. Measured in one run, both arms:
  # under 200 added caller frames the boundary moves 2,497 → 2,447, exactly 200/4. That is
  # why the cap is a parameter and why the default leaves ~20% of the bare-probe boundary as
  # headroom: `gen-memo`'s `lib/{build,provenance,structural}.nix` call from inside build,
  # provenance and structural stacks, so their real ceiling is strictly lower than any bare
  # figure and they lower `maxDepth` rather than reading 2,000 as a promise.
  #
  # The cap rides on the caller's own accessor record, which is the shape `fixpoint.closureOf`
  # already uses for `maxIter` (ADR-0009's fourth amendment: refuse BY NAME at the ceiling;
  # ADR-0032: owed where a real ceiling exists, and only there). `preorder.nix`'s walks and
  # `ancestorsOf` once carried the same cap; they are `genericClosure` loops now, with no
  # ceiling, so this is the one self-recursive core left in the class.
  pathsMaxDepth = 2000;

  pathsBetween =
    {
      edges,
      maxDepth ? pathsMaxDepth,
      ...
    }:
    startId: endId:
    let
      e = edgesAccessor "pathsBetween" edges;
      dfs =
        depth: visited: current:
        if current == endId then
          [ [ endId ] ]
        else if visited ? ${attrKey current} then
          [ ]
        # After both terminating checks: neither descends, so neither can reach the evaluator's ceiling, and refusing on one would change the
        # answer for graphs that never approach the cap.
        else if depth > maxDepth then
          throw "gen-graph.pathsBetween: path depth exceeded the stated cap of ${toString maxDepth}. This DFS is self-recursive, so the evaluator's call depth is the length of the path being extended; past the evaluator's own max-call-depth the failure is an uncatchable abort, and this cap sits below it so the refusal arrives first and `builtins.tryEval` can observe it. Set `maxDepth` on the accessor to match the stack the caller is itself nested in."
        else
          let
            newVisited = visited // {
              ${attrKey current} = true;
            };
            targets = (
              let
                es = e current;
              in
              if builtins.isList es then es else throw (notEdgeList "pathsBetween" current es)
            );
          in
          builtins.concatMap (
            next: map (path: [ current ] ++ path) (dfs (depth + 1) newVisited next)
          ) targets;
    in
    builtins.seq (identifier "pathsBetween" startId) (
      builtins.seq (identifier "pathsBetween" endId) (dfs 1 { } startId)
    );

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
      e = edgesAccessor "hoistEdges" edges;
      wrap =
        id:
        map (t: { key = t; }) (
          let
            es = e id;
          in
          if builtins.isList es then es else throw (notEdgeList "hoistEdges" id es)
        );
      wrapped = builtins.listToAttrs (
        map (id: {
          name = attrKey id;
          value = wrap id;
        }) nodes
      );
    in
    id:
    wrapped.${
      if builtins.isString id && builtins.hasContext id then
        builtins.unsafeDiscardStringContext id
      else
        id
    } or (wrap id);

  # `succ` is a hoisted successor function — `hoistEdges accessor`, or that composed with a
  # per-round restriction, which is how a caller whose accessor narrows between traversals
  # still hoists the part that does not (`lib/partition.nix`, the worklist arm).
  closureVia =
    who: succ: startId:
    let
      want = "a list of { key = <node id>; }";
      s = callableAt who "succ" want succ;
      # The element shape is this library's own `succ` contract, and it is tested by primops alone,
      # so a visit costs no lambda call. The TYPE of `key` is den-hoag-3w9e7's node-id ruling and is
      # not tested here.
      notSucc =
        id: xs:
        if builtins.isList xs then
          throw "gen-graph.${who}: succ ${renderId id} returned a list holding an element that is not { key = <node id>; }"
        else
          badResult who "succ" (renderId id) want xs;
    in
    builtins.genericClosure {
      startSet =
        let
          xs = s startId;
        in
        if
          builtins.isList xs
          && builtins.all builtins.isAttrs xs
          && builtins.length (builtins.catAttrs "key" xs) == builtins.length xs
        then
          xs
        else
          notSucc startId xs;
      operator =
        item:
        let
          xs = s item.key;
        in
        if
          builtins.isList xs
          && builtins.all builtins.isAttrs xs
          && builtins.length (builtins.catAttrs "key" xs) == builtins.length xs
        then
          xs
        else
          notSucc item.key xs;
    };

  # The hoisted readings of `reachableFrom` and `selfReachable`: same closure, same exclusion
  # of the start, same self-reappearance test, with the wrapping lifted out of the operator.
  reachableVia =
    succ: startId:
    builtins.seq (nodeKey "reachableVia" startId) (
      builtins.filter (id: id != startId) (map (r: r.key) (closureVia "reachableVia" succ startId))
    );

  selfReachableVia =
    succ: id:
    builtins.seq (nodeKey "selfReachableVia" id) (
      builtins.any (r: r.key == id) (closureVia "selfReachableVia" succ id)
    );
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
