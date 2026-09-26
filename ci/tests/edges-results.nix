# ── A PLAIN ACCESSOR'S RESULT IS REFUSED WHERE IT IS READ (den-hoag-0mqv1) ─────────────────────
# Every surface taking `{ edges, ... }` applies `edges` and reads the result as a list. Unguarded, a
# result that is not a list aborted past `tryEval` (`expected a list but found an integer`), an
# `edges` that is not a function aborted on its first application, and `leaves` answered a
# plausible wrong value at exit 0. These cells assert every surface refuses CATCHABLY; the messages
# are pinned on `testsError` (`ci/tests-error.nix`, `edges-results`).
{ genGraph, ... }:
let
  G = genGraph;
  good =
    id:
    if id == "a" then
      [ "b" ]
    else if id == "b" then
      [
        "a"
        "c"
      ]
    else
      [ ];
  bad = id: if id == "b" then 1 else good id;
  nodes = [
    "a"
    "b"
    "c"
  ];
  acc = e: {
    edges = e;
    inherit nodes;
  };
  # an acyclic variant, so the ordering surfaces answer rather than report a cycle
  acyclic = e: if builtins.isFunction e then (id: if id == "a" then [ ] else e id) else e;
  registry = {
    a = { };
    b = { };
    c = { };
  };
  surfaces = e: {
    reachableFrom = G.reachableFrom (acc e) "a";
    reachableWhere = G.reachableWhere (acc e) "a" (_: true);
    canReach = G.canReach (acc e) "a" "c";
    selfReachable = G.selfReachable (acc e) "a";
    pathsBetween = G.pathsBetween (acc e) "a" "c";
    hoistEdges = G.hoistEdges (acc e) "b";
    reachableVia = G.reachableVia (G.hoistEdges (acc e)) "a";
    cycles = G.cycles (acc e);
    cyclePaths = G.cyclePaths (acc e);
    dependents = G.dependents (acc e) "c";
    dependentsOf = G.dependentsOf (acc e) "c";
    impactOf = G.impactOf (acc e) "c";
    dependentsFrontier = G.dependentsFrontier (acc e) "c" (_: true);
    transpose = (G.transpose (acc e)).edges "a";
    condensationClosure = G.condensationClosure (acc e);
    coScc = G.coScc (acc e) "a" "c";
    directDependents = G.directDependents (acc e);
    directDependentsOf = G.directDependentsOf (acc e) "a";
    roots = G.roots (acc e);
    materialize = G.materialize (acc e);
    transitiveClosure = G.transitiveClosure (acc e);
    transitiveReduction = G.transitiveReduction (acc e);
    condensation = G.condensation (acc e);
    fbNode = G.fbNode (acc e);
    fbWork = G.fbWork (acc e);
    lowlink = G.lowlink (acc e);
    condensationOf = G.condensationOf (acc e) {
      a = "a";
      b = "a";
      c = "c";
    };
    topoOrder = G.topoOrder { } (acc (acyclic e));
    topoOrderKahn = G.topoOrderKahn { } (acc (acyclic e));
    coneRank = G.coneRank (acc (acyclic e)) nodes;
    expandPreorder = G.expandPreorder {
      roots = [ "a" ];
      key = f: f;
      edges = e;
    };
    foldReach = G.foldReach {
      roots = [ { t = "a"; } ];
      edges =
        if builtins.isFunction e then
          (
            id:
            let
              r = e id;
            in
            if builtins.isList r then map (t: { inherit t; }) r else r
          )
        else
          e;
      target = x: x.t;
      project = x: [ x.t ];
      itemKey = x: x;
    };
    fromRegistry = G.reachableFrom (G.fromRegistry {
      inherit registry;
      edges = if builtins.isFunction e then (id: _entry: e id) else e;
    }) "a";
  };
  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  admittedOf = arms: builtins.filter (k: admitted arms.${k}) (builtins.attrNames arms);
in
{
  flake.tests.edges-results = {
    test-every-plain-accessor-surface-refuses-a-non-list-result-catchably = {
      expr = admittedOf (surfaces bad);
      expected = [ ];
    };
    test-every-plain-accessor-surface-refuses-a-non-function-edges-catchably = {
      expr = admittedOf (surfaces 1);
      expected = [ ];
    };
    # a walk STARTED at the bad node reads it at its first application, the start set, which the
    # walks from "a" above never reach
    test-a-walk-started-at-a-non-list-result-refuses-catchably = {
      expr = admittedOf {
        reachableFrom = G.reachableFrom (acc bad) "b";
        reachableWhere = G.reachableWhere (acc bad) "b" (_: true);
        canReach = G.canReach (acc bad) "b" "c";
        coScc = G.coScc (acc bad) "b" "c";
        selfReachable = G.selfReachable (acc bad) "b";
      };
      expected = [ ];
    };
    # a set whose `__functor` is not a function is not callable, at the plain accessor as at `edgesAt`
    test-a-functor-that-is-not-callable-is-refused-catchably = {
      expr = admittedOf (surfaces {
        __functor = 1;
      });
      expected = [ ];
    };
    # `leaves` compared the result with `[ ]`, so a non-list was answered as "not a leaf" at exit 0
    test-leaves-refuses-a-non-list-result-rather-than-answering = {
      expr = admitted (G.leaves (acc bad));
      expected = false;
    };
    # CONTROL: the same constructions with a lawful accessor answer, so the refusals above are the
    # guards and not a broken fixture
    test-the-lawful-accessor-answers-on-every-surface = {
      expr = {
        admitted = builtins.length (admittedOf (surfaces good));
        total = builtins.length (builtins.attrNames (surfaces good));
        leaves = G.leaves (acc good);
        reachableFrom = G.reachableFrom (acc good) "a";
      };
      expected = {
        admitted = 33;
        total = 33;
        leaves = [ "c" ];
        reachableFrom = [
          "b"
          "c"
        ];
      };
    };
    # NO EARLIER: a result is checked where it is read, so a node the surface never expands is never
    # refused — `canReach` stops at its target and a walk from a sink reads nothing past it
    test-an-unread-result-is-not-refused = {
      expr = {
        canReach = G.canReach (acc bad) "a" "b";
        reachableFrom = G.reachableFrom (acc bad) "c";
        hoisted = G.hoistEdges (acc bad) "a";
      };
      expected = {
        canReach = true;
        reachableFrom = [ ];
        hoisted = [ { key = "b"; } ];
      };
    };
  };
}
