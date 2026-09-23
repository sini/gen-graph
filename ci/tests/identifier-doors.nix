# THE IDENTIFIER DOORS (den-hoag-bkdkg, ADR-0025 item 1): a door taking a node id refuses a value
# that is never one, by name and catchably; the message cells live on `testsError`
# (`identifier-refusal`). This file holds what the refusal must NOT change and the one thing an
# error cell cannot say: that the refusal is a throw `tryEval` observes, not an interpreter abort.
{ genGraph, ... }:
let
  G = genGraph;
  es = {
    a = [ "b" ];
    b = [ ];
  };
  g = {
    edges = id: es.${id} or [ ];
    nodes = [
      "a"
      "b"
    ];
    parent = id: if id == "b" then "a" else null;
  };
  X = {
    name = "a";
  };
  lg = G.labeledFrom {
    nodes = [
      "a"
      "b"
    ];
    perLabel.l = id: es.${id} or [ ];
  };
  qa = from: {
    graph = lg;
    inherit from;
    follow = G.regex.parse "l*";
  };
  refused = v: !(builtins.tryEval (builtins.deepSeq v true)).success;

  # Integer ids, under an accessor keyed on them. The doors whose bodies only hand the id to the
  # accessor, `genericClosure` and `==` answer correctly here, and the guard keeps them doing so.
  ie = n: if n < 3 then [ (n + 1) ] else [ ];
  succ = n: map (k: { key = k; }) (ie n);
  iq = {
    graph = {
      labeledEdges = _: [ ];
      nodes = [ 0 ];
    };
    from = 0;
    follow = G.regex.parse "l*";
  };
in
{
  flake.tests.identifier-doors = {
    # Each door handed a node VALUE where its id goes; every one is a CATCHABLE refusal. Before the
    # guards, fourteen of these aborted past `tryEval` and three answered a plausible value.
    test-a-node-value-is-refused-catchably-at-every-identifier-door = {
      expr = map refused [
        (G.reachableFrom g X)
        (G.reachableWhere g X (_: true))
        (G.canReach g X "b")
        (G.canReach g "a" X)
        (G.selfReachable g X)
        (G.ancestorsOf g X)
        (G.pathsBetween g X "b")
        (G.dependents g X)
        (G.dependentsOf g X)
        (G.dependentsFrontier g X (_: false))
        (G.impactOf g X)
        (G.directDependentsOf g X)
        (G.coScc g X "b")
        (G.reachableVia (G.hoistEdges g) X)
        (G.selfReachableVia (G.hoistEdges g) X)
        (G.query (qa X))
        (G.queryArrivals (qa X // { advance = _: 1; }))
      ];
      expected = builtins.genList (_: true) 17;
    };
    test-a-member-id-still-answers-at-every-identifier-door = {
      expr = [
        (G.reachableFrom g "a")
        (G.reachableWhere g "a" (_: true))
        (G.canReach g "a" "b")
        (G.selfReachable g "a")
        (G.ancestorsOf g "b")
        (G.pathsBetween g "a" "b")
        (G.dependents g "b")
        (G.dependentsOf g "b")
        (G.impactOf g "b")
        (G.directDependentsOf g "b")
        (G.coScc g "a" "b")
        (G.reachableVia (G.hoistEdges g) "a")
        (G.query (qa "a"))
        (map (a: a.node) (G.queryArrivals (qa "a" // { advance = _: 1; })))
      ];
      expected = [
        [ "b" ]
        [ "b" ]
        true
        false
        [ "a" ]
        [
          [
            "a"
            "b"
          ]
        ]
        [ "a" ]
        [ "a" ]
        [ "a" ]
        [ "a" ]
        false
        [ "b" ]
        [
          "a"
          "b"
        ]
        [
          "a"
          "b"
        ]
      ];
    };
    # den-hoag-bkdkg C1: these bodies are key-polymorphic, and the guard does not narrow them.
    test-the-key-polymorphic-doors-still-answer-on-integer-ids = {
      expr = [
        (G.reachableFrom { edges = ie; } 0)
        (G.reachableWhere { edges = ie; } 0 (_: true))
        (G.canReach { edges = ie; } 0 3)
        (G.canReach { edges = ie; } 3 0)
        (G.selfReachable { edges = ie; } 0)
        (G.coScc { edges = ie; } 0 1)
        (G.reachableVia succ 0)
        (G.selfReachableVia succ 0)
        (map (a: a.node) (G.queryArrivals (iq // { advance = _: 1; })))
        (G.query (iq // { mode = "series"; }))
      ];
      expected = [
        [
          1
          2
          3
        ]
        [
          1
          2
          3
        ]
        true
        false
        false
        false
        [
          1
          2
          3
        ]
        false
        [ 0 ]
        [ 0 ]
      ];
    };
    # The guards live in the door bodies, so the published formals survive: a guard at an export
    # wrapper would read `{ }` here (measured on the rejected prototype, `roots`).
    test-the-published-argument-lists-survive = {
      expr = map builtins.functionArgs [
        G.roots
        G.reachableFrom
        G.ancestorsOf
        G.dependentsOf
        G.impactOf
        G.queryFold
      ];
      expected = [
        {
          edges = false;
          nodes = false;
        }
        { edges = false; }
        {
          parent = false;
          maxDepth = true;
        }
        {
          edges = false;
          nodes = false;
        }
        {
          edges = false;
          nodes = false;
        }
        {
          empty = false;
          combine = false;
          valueOf = true;
        }
      ];
    };
  };
}
