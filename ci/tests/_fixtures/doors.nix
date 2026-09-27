# NOT A SUITE. The door family (den-hoag-7gp66 P1, spec §v1.2/§v1.7): every published door that takes a
# record composes gen-prelude's `checkOptions` / `checkRequired`. `ci/tests/doors.nix` asserts the
# refusals catchable and the valid call unchanged; `ci/tests-error.nix` (`door-refusals`,
# `door-naming`) pins them by message. Held once so both assert about the same objects. It sits under
# `_fixtures/` because the tree importer ignores any path with that segment.
#
# Per door: `door`, a `good` record the door accepts, and — for a door with required fields — the one
# `drop`ped to make it incomplete. RECORD doors are open (R5): an extra field is admitted. OPTIONS
# and MIXED doors are closed: an unknown field is refused. `unknown` is the field no door accepts.
{ genGraph }:
let
  G = genGraph;
  g = {
    nodes = [
      "a"
      "b"
    ];
    edges = id: { a = [ "b" ]; }.${id} or [ ];
  };
  isRegistered = id: builtins.elem id g.nodes;
  labeled = G.labeledFrom {
    perLabel.x = g.edges;
    inherit (g) nodes;
  };
in
{
  unknown = "notAFieldOfThisDoor";

  records = {
    mkNodeRef = {
      door = G.mkNodeRef;
      good = { inherit isRegistered; };
      drop = "isRegistered";
      required = [ "isRegistered" ];
    };
    nodeRefFindings = {
      door = G.nodeRefFindings;
      good = { inherit isRegistered; };
      drop = "isRegistered";
      required = [ "isRegistered" ];
    };
    mkEndpointProjection = {
      door = G.mkEndpointProjection;
      good = {
        childBearing = _: false;
        isNode = isRegistered;
      };
      drop = "isNode";
      required = [
        "childBearing"
        "isNode"
      ];
    };
    mkProjectionFindings = {
      door = G.mkProjectionFindings;
      good = {
        childBearing = _: false;
        isNode = isRegistered;
      };
      drop = "isNode";
      required = [
        "childBearing"
        "isNode"
      ];
    };
    labeledFrom = {
      door = G.labeledFrom;
      good = {
        perLabel.x = g.edges;
        inherit (g) nodes;
      };
      drop = "perLabel";
      required = [
        "perLabel"
        "nodes"
      ];
    };
  };

  options = {
    mkGraph = {
      door = G.mkGraph;
      good = { };
      accepted = [
        "edges"
        "parents"
        "nodeData"
      ];
    };
    topoOrder = {
      door = G.topoOrder;
      good = { };
      accepted = [
        "keyOf"
        "lessThan"
      ];
    };
    topoOrderKahn = {
      door = G.topoOrderKahn;
      good = { };
      accepted = [
        "keyOf"
        "lessThan"
      ];
    };
    "regex.parseWith" = {
      door = G.regex.parseWith;
      good = { };
      accepted = [ "maxLength" ];
    };
  };

  mixed = {
    fixpoint = {
      door = G.fixpoint;
      good = {
        seed = { };
        step = c: c;
      };
      drop = "step";
      required = [
        "seed"
        "step"
      ];
      accepted = [
        "seed"
        "step"
        "maxIter"
        "refusal"
      ];
    };
    seededFixpoint = {
      door = G.seededFixpoint;
      good = {
        seed = { };
        frontier = { };
        step = _: _: { };
      };
      drop = "frontier";
      required = [
        "seed"
        "frontier"
        "step"
      ];
      accepted = [
        "seed"
        "frontier"
        "step"
        "maxIter"
      ];
    };
    foldPreorder = {
      door = G.foldPreorder;
      good = {
        roots = [ "a" ];
        key = f: f;
        expand = acc: _: { inherit acc; };
        acc = 0;
      };
      drop = "expand";
      required = [
        "roots"
        "key"
        "expand"
        "acc"
      ];
      accepted = [
        "roots"
        "key"
        "expand"
        "acc"
        "visited"
        "maxDepth"
        "surface"
      ];
    };
    expandPreorder = {
      door = G.expandPreorder;
      good = {
        roots = [ "a" ];
        key = f: f;
        inherit (g) edges;
      };
      drop = "key";
      required = [
        "roots"
        "key"
        "edges"
      ];
      accepted = [
        "roots"
        "key"
        "edges"
        "resolve"
        "emit"
        "seen0"
        "nodes0"
        "maxDepth"
      ];
    };
    foldReach = {
      door = G.foldReach;
      good = {
        roots = [ ];
        inherit (g) edges;
        target = e: e;
        project = _: [ ];
        itemKey = i: i;
      };
      drop = "itemKey";
      required = [
        "roots"
        "edges"
        "target"
        "project"
        "itemKey"
      ];
      accepted = [
        "roots"
        "edges"
        "target"
        "project"
        "itemKey"
        "visited0"
        "seen0"
        "nodes0"
        "maxDepth"
      ];
    };
    fromRegistry = {
      door = G.fromRegistry;
      good = {
        registry = {
          a.deps = [ "b" ];
          b = { };
        };
        edges = G.field "deps";
      };
      drop = "registry";
      required = [
        "registry"
        "edges"
      ];
      accepted = [
        "registry"
        "edges"
        "parent"
      ];
    };
    fromScan = {
      door = G.fromScan;
      good = {
        items = [ ];
        scan = _: [ ];
        project = r: r;
      };
      drop = "scan";
      required = [
        "items"
        "scan"
        "project"
      ];
      accepted = [
        "items"
        "scan"
        "project"
        "nodeData"
        "parents"
      ];
    };
    queryArrivals = {
      door = G.queryArrivals;
      good = {
        graph = labeled;
        from = "a";
        follow = G.regex.parse "x*";
        advance = _: 1;
      };
      drop = "advance";
      required = [
        "graph"
        "from"
        "follow"
        "advance"
      ];
      accepted = [
        "graph"
        "from"
        "follow"
        "advance"
        "where"
      ];
    };
    # `queryAll`/`queryPaths` are not doors: they are reached only through `query` (modes `all` and
    # `paths`, plus `visible`/`layers`/`fixpoint` which thread through them internally) and through
    # `queryFold` (den-hoag-7gp66 P1, P-1). The formals check now runs at `query`/`queryFold`
    # themselves, so an unknown or missing field is refused catchably naming the door the caller
    # called, never the private function behind it.
    query = {
      door = G.query;
      good = {
        graph = labeled;
        from = "a";
        follow = G.regex.parse "x*";
      };
      drop = "follow";
      required = [
        "graph"
        "from"
        "follow"
      ];
      accepted = [
        "graph"
        "from"
        "follow"
        "where"
      ];
    };
    queryFold = {
      door = G.queryFold;
      good = {
        empty = 0;
        combine = a: _: a;
        graph = labeled;
        from = "a";
        follow = G.regex.parse "x*";
      };
      drop = "graph";
      required = [
        "graph"
        "from"
        "follow"
      ];
      accepted = [
        "graph"
        "from"
        "follow"
        "where"
      ];
    };
  };

  # R6 (§v1.7 "a primitive refusal naming the door"; spec cell 5): a door that reaches a shared
  # primitive refuses under ITS OWN name, `gen-graph.<door>: … (in <primitive>)`. `reached` drives each
  # door on an accessor whose `edges` returns an int, so the primitive's list check refuses; `cycles` is
  # spec cell 5 verbatim. `reachedByTarget` drives it on an int edge TARGET, which a primitive keys.
  bad = {
    nodes = [ "a" ];
    edges = _: 5;
  };
  says = "edges \"a\" returned a int, not a list of node ids";
  badTarget = {
    nodes = [ "a" ];
    edges = _: [ 1 ];
  };
  saysTarget = "got int, expected a node identifier (a string)";
  reachedByTarget = {
    dependents = {
      prim = "compose";
      run = a: G.dependents a "a";
    };
    transitiveClosure = {
      prim = "compose";
      run = a: G.transitiveClosure a;
    };
    transitiveReduction = {
      prim = "differenceEdges";
      run = a: G.transitiveReduction a;
    };
  };
  reached = {
    cycles = {
      prim = "lowlink";
      run = a: G.cycles a;
    };
    cyclePaths = {
      prim = "lowlink";
      run = a: G.cyclePaths a;
    };
    condensationClosure = {
      prim = "condensationOf";
      run = a: G.condensationClosure a;
    };
    dependents = {
      prim = "materialize";
      run = a: G.dependents a "a";
    };
    transitiveClosure = {
      prim = "materialize";
      run = a: G.transitiveClosure a;
    };
    transitiveReduction = {
      prim = "materialize";
      run = a: G.transitiveReduction a;
    };
    transpose = {
      prim = "materialize";
      run = a: (G.transpose a).edges "a";
    };
    directDependentsOf = {
      prim = "directDependents";
      run = a: G.directDependentsOf a "a";
    };
    reachableWhere = {
      prim = "reachableFrom";
      run = a: G.reachableWhere a "a" (_: true);
    };
    coScc = {
      prim = "canReach";
      run = a: G.coScc a "a" "b";
    };
  };
}
