{ genGraph, ... }:
let
  inherit (genGraph)
    query
    labeledFrom
    regex
    fixtures
    labeledFixtures
    reachableFrom
    ;
  r = regex;
  sorted = builtins.sort builtins.lessThan;
in
{
  flake.tests.query = {
    test-all-contains-closure = {
      expr = sorted (query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.star (r.lit "contains");
        mode = "all";
      });
      # star is nullable → root included
      expected = [
        "h1"
        "h2"
        "root"
        "u1"
        "u2"
        "vm1"
      ];
    };
    test-all-non-nullable-excludes-from = {
      expr = sorted (query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.plus (r.lit "contains");
        mode = "all";
      });
      expected = [
        "h1"
        "h2"
        "u1"
        "u2"
        "vm1"
      ];
    };
    test-all-two-step-word = {
      # contains contains → exactly depth-2 targets
      expr = sorted (query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.parse "contains contains";
        mode = "all";
      });
      expected = [
        "u1"
        "vm1"
      ];
    };
    test-all-mixed-labels = {
      # member include? from g1 → members and what they include
      expr = sorted (query {
        graph = labeledFixtures.world;
        from = "g1";
        follow = r.parse "member include?";
        mode = "all";
      });
      expected = [
        "shared"
        "u1"
        "u2"
      ];
    };
    test-all-where-filters = {
      expr = query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.parse "contains*";
        mode = "all";
        where = id: id == "vm1";
      };
      expected = [ "vm1" ];
    };
    test-all-cycle-terminates = {
      expr = sorted (query {
        graph = labeledFixtures.cyclic;
        from = "a";
        follow = r.parse "contains* member";
        mode = "all";
      });
      expected = [ "m" ];
    };
    test-all-wrong-label-blocked = {
      expr = query {
        graph = labeledFixtures.world;
        from = "g1";
        follow = r.parse "contains";
        mode = "all";
      };
      expected = [ ];
    };
    test-labeled-from-adapter = {
      # per-label plain accessors (the gen-scope followEdge shape) → labeledEdges
      expr = sorted (query {
        graph = labeledFrom {
          contains =
            id:
            {
              root = [
                "h1"
                "h2"
              ];
              h1 = [ "u1" ];
            }
            .${id} or [ ];
          member = id: { g1 = [ "u1" ]; }.${id} or [ ];
        };
        from = "root";
        follow = r.parse "contains+";
        mode = "all";
      });
      expected = [
        "h1"
        "h2"
        "u1"
      ];
    };
    test-subsumes-reachable-from = {
      # lift label-blind fixtures; star-any closure == reachableFrom (+ start).
      # cyclic is the load-bearing case (termination + set equality through a cycle).
      expr =
        let
          check =
            fx: from:
            let
              lifted = labeledFrom { edge = id: fx.edges id; };
              viaQuery = builtins.filter (x: x != from) (query {
                graph = lifted;
                inherit from;
                follow = r.star r.any;
                mode = "all";
              });
            in
            sorted viaQuery == sorted (reachableFrom fx from);
        in
        check fixtures.diamond "a" && check fixtures.cyclic "a";
      expected = true;
    };
    test-laziness-poison-unreached = {
      expr = query {
        graph = labeledFixtures.poisoned;
        from = "a";
        follow = r.parse "safe";
        mode = "all";
      };
      expected = [ "b" ];
    };
    test-all-dedup-across-nullable-states = {
      # n reached in TWO distinct nullable derivative states (residuals e and (e|'z));
      # answers are a SET — one entry. Also covers parallel same-target edges.
      expr = query {
        graph = labeledFrom {
          x = id: { s = [ "n" ]; }.${id} or [ ];
          y = id: { s = [ "n" ]; }.${id} or [ ];
        };
        from = "s";
        follow = r.parse "x | y z?";
        mode = "all";
      };
      expected = [ "n" ];
    };
  };
}
