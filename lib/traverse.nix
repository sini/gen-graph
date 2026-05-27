# Lazy graph traversal via accessor functions.
#
# Uses builtins.genericClosure (C-level BFS with native dedup) for
# reachability queries. ~4-5x faster than Nix-level BFS on large graphs.
{ lib }:
let
  # Follow edges transitively from a start node (excludes startId).
  # C-level BFS via genericClosure. O(reachable nodes).
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

  # Point query: can fromId reach toId? O(reachable from fromId).
  # Does NOT require materializing the full graph.
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
