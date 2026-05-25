# Built-in query primitives via monotonic combinators.
{ lib, sets, combinators }:
let
  # Internal: extract only import edges (I-label) from a node map
  importEdges = nodes:
    combinators.selectEdges (sets.fromEdges nodes) (e: e.label == "I");

  # Internal: transitive closure of import edges
  transitiveClosure = nodes:
    let iEdges = importEdges nodes;
    in combinators.fixpoint {
      seed = iEdges;
      step = current: sets.unionEdges current (combinators.compose current iEdges);
    };

  # Internal: reverse all edges in an edge set
  transpose = edgeSet:
    builtins.foldl' (acc: from:
      builtins.foldl' (acc2: to:
        let
          existing = acc2.${to} or {};
          e = edgeSet.${from}.${to};
        in
        acc2 // { ${to} = existing // { ${from} = e // { from = to; to = from; }; }; }
      ) acc (builtins.attrNames edgeSet.${from})
    ) {} (builtins.attrNames edgeSet);

  self = {
    reachableFrom = nodes: startId:
      builtins.attrNames ((transitiveClosure nodes).${startId} or {});

    # Predicate-filtered reachability (Arntzenius 2016).
    reachableWhere = nodes: startId: pred:
      builtins.filter (id: pred (nodes.${id} or {})) (self.reachableFrom nodes startId);

    dependents = nodes: targetId:
      let
        closure = transitiveClosure nodes;
        reversed = transpose closure;
      in
      builtins.attrNames (reversed.${targetId} or {});

    impactOf = self.dependents;

    # P-edge upward traversal (Neron 2015 — P* path).
    ancestorsOf = nodes: startId:
      let
        go = visited: id:
          let p = (nodes.${id} or {}).parent or null;
          in if p == null then []
          else if visited ? ${p} then
            throw "gen-graph: ancestorsOf: cycle detected at '${p}'"
          else [p] ++ go (visited // { ${p} = true; }) p;
      in go { ${startId} = true; } startId;

    roots = nodes:
      let
        iEdges = importEdges nodes;
        allTargets = builtins.listToAttrs (lib.concatMap (from:
          map (to: { name = to; value = true; }) (builtins.attrNames iEdges.${from})
        ) (builtins.attrNames iEdges));
      in
      builtins.sort builtins.lessThan
        (builtins.filter (n: !(allTargets ? ${n})) (builtins.attrNames nodes));

    leaves = nodes:
      let allSources = importEdges nodes;
      in builtins.sort builtins.lessThan
        (builtins.filter (n: !(allSources ? ${n})) (builtins.attrNames nodes));

    # Nodes in any cycle (self-reachable in transitive closure)
    cycles = nodes:
      let closure = transitiveClosure nodes;
      in builtins.sort builtins.lessThan (builtins.filter (id:
        (closure.${id} or {}) ? ${id}
      ) (builtins.attrNames nodes));

    # Transitive reduction: minimal edge set preserving reachability (Mokhov 2017 §4.5).
    transitiveReduction = nodes:
      let
        iEdges = importEdges nodes;
        closure = transitiveClosure nodes;
        redundant = lib.mapAttrs (from: targets:
          lib.filterAttrs (to: _:
            builtins.any (mid:
              mid != to && ((closure.${mid} or {}) ? ${to})
            ) (builtins.attrNames targets)
          ) targets
        ) iEdges;
      in
      sets.differenceEdges iEdges redundant;

    # All acyclic paths between two nodes (DFS with visited set)
    pathsBetween = nodes: startId: endId:
      let
        iEdges = importEdges nodes;
        dfs = visited: current:
          if current == endId then [ [ endId ] ]
          else if visited ? ${current} then []
          else
            let
              neighbors = builtins.attrNames (iEdges.${current} or {});
              newVisited = visited // { ${current} = true; };
            in
            builtins.concatMap (next:
              builtins.map (path: [ current ] ++ path) (dfs newVisited next)
            ) neighbors;
      in dfs {} startId;
  };
in self
