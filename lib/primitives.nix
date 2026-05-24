# Built-in query primitives via monotonic combinators.
# Scope-engine-aware queries (visibleFrom, ambiguities) call scope-engine resolution.
{ lib, sets, combinators, engine }:
let
  requireEngine = name:
    if engine == null
    then throw "gen-graph: ${name} requires scope-engine (pass engine argument to gen-graph)"
    else null;

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

    dependents = nodes: targetId:
      let
        closure = transitiveClosure nodes;
        reversed = transpose closure;
      in
      builtins.attrNames (reversed.${targetId} or {});

    impactOf = self.dependents;

    roots = nodes:
      let
        iEdges = importEdges nodes;
        allTargets = lib.unique (lib.concatMap (from:
          builtins.attrNames iEdges.${from}
        ) (builtins.attrNames iEdges));
      in
      builtins.sort builtins.lessThan
        (builtins.filter (n: !(builtins.elem n allTargets)) (builtins.attrNames nodes));

    leaves = nodes:
      let allSources = builtins.attrNames (importEdges nodes);
      in builtins.sort builtins.lessThan
        (builtins.filter (n: !(builtins.elem n allSources)) (builtins.attrNames nodes));

    # Nodes in any cycle (self-reachable in transitive closure)
    cycles = nodes:
      let closure = transitiveClosure nodes;
      in builtins.sort builtins.lessThan (builtins.filter (id:
        (closure.${id} or {}) ? ${id}
      ) (builtins.attrNames nodes));

    # All acyclic paths between two nodes (DFS with visited set)
    pathsBetween = nodes: startId: endId:
      let
        iEdges = importEdges nodes;
        dfs = visited: current:
          if current == endId then [ [ endId ] ]
          else if builtins.elem current visited then []
          else
            let
              neighbors = builtins.attrNames (iEdges.${current} or {});
              newVisited = visited ++ [ current ];
            in
            builtins.concatMap (next:
              builtins.map (path: [ current ] ++ path) (dfs newVisited next)
            ) neighbors;
      in dfs [] startId;

    # Scope-engine-aware: Neron visible declaration from a scope
    visibleFrom = dataFilter: result: nodeId:
      builtins.seq (requireEngine "visibleFrom")
      (engine.query { inherit dataFilter; } result nodeId);

    # Scope-engine-aware: nodes with ambiguous resolution
    ambiguities = dataFilter: nodes: result:
      builtins.seq (requireEngine "ambiguities")
      (builtins.filter (id:
        engine.ambiguous { inherit dataFilter; } result id
      ) (builtins.attrNames nodes));
  };
in self
