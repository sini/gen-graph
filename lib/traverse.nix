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
# out-edge read. Consumers state their cost in this form, never as O(reachable); `cycles` runs
# the sum once per node, which is where its Θ(n³) dense figure comes from.
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

  # Point query: can fromId reach toId? Θ( Σ_{u ∈ reach fromId} (1 + outdeg u) ) — the same
  # per-visit cost as reachableFrom, since it is the same operator, so O(reachable) only at
  # bounded out-degree.
  # genericClosure is strict, so fromId's closure is materialized in full on every call;
  # builtins.any short-circuits its scan of that finished list, not the traversal that built
  # it. What is avoided is the whole-graph transitive closure, not the per-call one.
  canReach =
    { edges, ... }:
    fromId: toId:
    builtins.any (r: r.key == toId) (
      builtins.genericClosure {
        startSet = map (id: { key = id; }) (edges fromId);
        operator = item: map (id: { key = id; }) (edges item.key);
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
in
{
  inherit
    reachableFrom
    reachableWhere
    canReach
    selfReachable
    ancestorsOf
    pathsBetween
    ;
}
