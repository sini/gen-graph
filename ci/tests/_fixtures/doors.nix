# NOT A SUITE. The door family (den-hoag-7gp66 P1, then P2): every published step that takes a record
# is a `prelude.door` — an OPTIONS step (closed) or a RECORD step (open, R5). `ci/tests/doors.nix`
# asserts the refusals catchable, the valid call unchanged and the published contract equal to the
# row; `ci/tests-error.nix` (`door-refusals`, `door-naming`) pins them by message. Held once so both
# assert about the same objects. It sits under `_fixtures/` because the tree importer ignores any
# path with that segment.
#
# `unknown` is the field no door accepts. A positional step is not a door (P2 §p2.3.2: no field
# contract to publish), so the operands that left a record for positions are not rows here.
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
    x = g.edges;
  } g.nodes;
in
{
  unknown = "notAFieldOfThisDoor";

  # The options steps whose next step is NOT a record door, so there is no record for G10 to guard:
  # a positional operand (`fixpoint`, `fromRegistry`, `regex.parseWith`) or a value (`mkGraph`).
  # `ci/tests/doors.nix` enumerates every options door on the published surface and requires each
  # to be here or to have a `records` row, so a new chained door cannot go unguarded unseen (P6).
  notChained = [
    "mkGraph"
    "fixpoint"
    "fromRegistry"
    "regex.parseWith"
  ];

  # ── EVERY OPTIONS STEP (P2 rule 2) ──
  # Closed: `{ }` is admitted, an unknown field is refused catchably when the options are applied
  # (G1/G4), and the published contract is this row's `optional` (D3). `name` is the door's name
  # where it is not the row's.
  options = {
    mkGraph = {
      door = G.mkGraph;
      optional = [
        "edges"
        "parents"
        "nodeData"
      ];
    };
    topoOrder = {
      door = G.topoOrder;
      optional = [
        "keyOf"
        "lessThan"
      ];
    };
    topoOrderKahn = {
      door = G.topoOrderKahn;
      optional = [
        "keyOf"
        "lessThan"
      ];
    };
    "regex.parseWith" = {
      door = G.regex.parseWith;
      optional = [ "maxLength" ];
    };
    fixpoint = {
      door = G.fixpoint;
      optional = [
        "maxIter"
        "refusal"
      ];
    };
    fromRegistry = {
      door = G.fromRegistry;
      optional = [ "parent" ];
    };
    ancestorsOf = {
      door = G.ancestorsOf;
      optional = [ "maxDepth" ];
    };
    pathsBetween = {
      door = G.pathsBetween;
      optional = [ "maxDepth" ];
    };
    dependents = {
      door = G.dependents;
      optional = [ "maxIter" ];
    };
    condensationClosure = {
      door = G.condensationClosure;
      optional = [ "maxIter" ];
    };
    transitiveClosure = {
      door = G.transitiveClosure;
      optional = [ "maxIter" ];
    };
    transitiveReduction = {
      door = G.transitiveReduction;
      optional = [ "maxIter" ];
    };
    closureOf = {
      door = G.closureOf "transitiveClosure";
      name = "transitiveClosure";
      optional = [ "maxIter" ];
    };
    seededFixpoint = {
      door = G.seededFixpoint;
      optional = [ "maxIter" ];
    };
    foldPreorder = {
      door = G.foldPreorder;
      optional = [
        "visited"
        "maxDepth"
        "surface"
      ];
    };
    expandPreorder = {
      door = G.expandPreorder;
      optional = [
        "resolve"
        "emit"
        "seen0"
        "nodes0"
        "maxDepth"
      ];
    };
    foldReach = {
      door = G.foldReach;
      optional = [
        "visited0"
        "seen0"
        "nodes0"
        "maxDepth"
      ];
    };
    fromScan = {
      door = G.fromScan;
      optional = [
        "nodeData"
        "parents"
      ];
    };
    queryArrivals = {
      door = G.queryArrivals;
      optional = [ "where" ];
    };
    queryFold = {
      door = G.queryFold;
      optional = [
        "valueOf"
        "where"
      ];
    };
    query = {
      door = G.query;
      optional = [
        "mode"
        "where"
        "order"
        "groupBy"
        "combine"
        "empty"
        "valueOf"
      ];
    };
  };

  # ── EVERY RECORD STEP (P2 rules 3 and 5, R7 (b)) ──
  # Open (R5): `good` is admitted, `drop` refused catchably by name at the step's application, an
  # extra field admitted, and the published contract is this row's `required` (D3). A record step
  # behind an options step carries `misplaced`, one of that step's own option names: it is refused
  # by name (`optionsStep`, G10) while an unrelated extra field is still admitted (G10-ctl).
  records =
    let
      acc = {
        inherit (g) edges nodes;
      };
      accessor = step: {
        inherit step;
        good = acc;
        drop = "edges";
        required = [
          "edges"
          "nodes"
        ];
      };
      edgesOnly = step: {
        inherit step;
        good = {
          inherit (g) edges;
        };
        drop = "edges";
        required = [ "edges" ];
      };
      closure =
        step:
        accessor step
        // {
          misplaced = "maxIter";
        };
      labeledRow = step: {
        inherit step;
        good = labeled;
        drop = "labeledEdges";
        required = [
          "labeledEdges"
          "nodes"
        ];
      };
      q = {
        graph = labeled;
        from = "a";
        follow = G.regex.parse "x*";
      };
      qRequired = [
        "graph"
        "from"
        "follow"
      ];
    in
    {
      reachableFrom = edgesOnly G.reachableFrom;
      reachableWhere = edgesOnly G.reachableWhere;
      canReach = edgesOnly G.canReach;
      selfReachable = edgesOnly G.selfReachable;
      coScc = edgesOnly G.coScc;
      coneRank = edgesOnly G.coneRank;
      hoistEdges = accessor G.hoistEdges;
      dependentsOf = accessor G.dependentsOf;
      dependentsFrontier = accessor G.dependentsFrontier;
      impactOf = accessor G.impactOf;
      directDependents = accessor G.directDependents;
      directDependentsOf = accessor G.directDependentsOf;
      materialize = accessor G.materialize;
      roots = accessor G.roots;
      leaves = accessor G.leaves;
      condensationOf = accessor G.condensationOf;
      fbNode = accessor G.fbNode;
      fbWork = accessor G.fbWork;
      lowlink = accessor G.lowlink;
      cycles = accessor G.cycles;
      cyclePaths = accessor G.cyclePaths;
      condensation = accessor G.condensation;
      transpose = accessor G.transpose;
      dependents = closure (G.dependents { });
      condensationClosure = closure (G.condensationClosure { });
      transitiveClosure = closure (G.transitiveClosure { });
      transitiveReduction = closure (G.transitiveReduction { });
      closureOf = closure (G.closureOf "transitiveClosure" { }) // {
        name = "transitiveClosure";
      };
      topoOrder = accessor (G.topoOrder { }) // {
        drop = "nodes";
        required = [
          "nodes"
          "edges"
        ];
        misplaced = "keyOf";
      };
      topoOrderKahn = accessor (G.topoOrderKahn { }) // {
        drop = "nodes";
        required = [
          "nodes"
          "edges"
        ];
        misplaced = "keyOf";
      };
      materializeParents = {
        step = G.materializeParents;
        good = {
          inherit (g) nodes;
          parent = _: null;
        };
        drop = "parent";
        required = [
          "nodes"
          "parent"
        ];
      };
      select = {
        step = G.select;
        good = {
          inherit (g) nodes;
          nodeData = _: { };
        };
        drop = "nodeData";
        required = [
          "nodes"
          "nodeData"
        ];
      };
      ancestorsOf = {
        step = G.ancestorsOf { };
        good = {
          parent = _: null;
        };
        drop = "parent";
        required = [ "parent" ];
        misplaced = "maxDepth";
      };
      pathsBetween = edgesOnly (G.pathsBetween { }) // {
        misplaced = "maxDepth";
      };
      forgetLabels = labeledRow G.forgetLabels;
      labeledTranspose = labeledRow G.labeledTranspose;
      compose = {
        step = G.compose;
        good = {
          first = { };
          second = { };
        };
        drop = "second";
        required = [
          "first"
          "second"
        ];
      };
      differenceEdges = {
        step = G.differenceEdges;
        good = {
          minuend = { };
          subtrahend = { };
        };
        drop = "subtrahend";
        required = [
          "minuend"
          "subtrahend"
        ];
      };
      entryBetween = {
        step = G.entryBetween;
        good = {
          before = [ ];
          after = [ ];
        };
        drop = "after";
        required = [
          "before"
          "after"
        ];
      };
      seededFixpoint = {
        step = G.seededFixpoint { };
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
        misplaced = "maxIter";
      };
      foldPreorder = {
        step = G.foldPreorder { };
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
        misplaced = "visited";
      };
      expandPreorder = {
        step = G.expandPreorder { };
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
        misplaced = "emit";
      };
      foldReach = {
        step = G.foldReach { };
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
        misplaced = "seen0";
      };
      fromScan = {
        step = G.fromScan { };
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
        misplaced = "nodeData";
      };
      queryArrivals = {
        step = G.queryArrivals { };
        good = q // {
          advance = _: 1;
        };
        drop = "advance";
        required = qRequired ++ [ "advance" ];
        misplaced = "where";
      };
      query = {
        step = G.query { };
        good = q;
        drop = "follow";
        required = qRequired;
        misplaced = "mode";
      };
      queryFold = {
        step = G.queryFold { } (a: _: a) 0;
        good = q;
        drop = "graph";
        required = qRequired;
        misplaced = "valueOf";
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
      run = a: G.dependents { } a "a";
    };
    transitiveClosure = {
      prim = "compose";
      run = a: G.transitiveClosure { } a;
    };
    transitiveReduction = {
      prim = "differenceEdges";
      run = a: G.transitiveReduction { } a;
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
      run = a: G.condensationClosure { } a;
    };
    dependents = {
      prim = "materialize";
      run = a: G.dependents { } a "a";
    };
    transitiveClosure = {
      prim = "materialize";
      run = a: G.transitiveClosure { } a;
    };
    transitiveReduction = {
      prim = "materialize";
      run = a: G.transitiveReduction { } a;
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
