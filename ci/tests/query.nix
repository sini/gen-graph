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
    test-paths-witness-shape = {
      expr = query {
        graph = labeledFixtures.world;
        from = "g1";
        follow = r.parse "member include";
        mode = "paths";
      };
      expected = [
        {
          node = "shared";
          path = [
            {
              label = "member";
              from = "g1";
              to = "u1";
            }
            {
              label = "include";
              from = "u1";
              to = "shared";
            }
          ];
        }
      ];
    };
    test-paths-diamond-both-witnesses = {
      expr =
        let
          g = labeledFrom {
            e =
              id:
              {
                a = [
                  "b"
                  "c"
                ];
                b = [ "d" ];
                c = [ "d" ];
              }
              .${id} or [ ];
          };
          res = query {
            graph = g;
            from = "a";
            follow = r.parse "e e";
            mode = "paths";
          };
        in
        builtins.length (builtins.filter (ans: ans.node == "d") res);
      expected = 2;
    };
    test-paths-cycle-terminates = {
      expr = builtins.length (query {
        graph = labeledFixtures.cyclic;
        from = "a";
        follow = r.parse "contains* member";
        mode = "paths";
      });
      expected = 1;
    };
    test-paths-nullable-start = {
      expr = builtins.head (query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.parse "contains*";
        mode = "paths";
        where = id: id == "root";
      });
      expected = {
        node = "root";
        path = [ ];
      };
    };
    test-paths-vs-all-self-loop-divergence = {
      # a self-loop witness needs a node revisit: `all` answers it ((node × state)
      # product), `paths` enumerates acyclic witnesses only — the documented
      # asymmetry, pinned so a visited-keying change can't silently move it.
      expr =
        let
          g = labeledFrom { hop = id: { s = [ "s" ]; }.${id} or [ ]; };
          common = {
            graph = g;
            from = "s";
            follow = r.parse "hop";
          };
        in
        {
          all = query (common // { mode = "all"; });
          paths = query (common // { mode = "paths"; });
        };
      expected = {
        all = [ "s" ];
        paths = [ ];
      };
    };
    test-visible-nearest-wins = {
      # x declared at own scope AND reachable via include: own wins, include shadowed
      expr =
        let
          g = labeledFrom {
            own = id: { s = [ "x@s" ]; }.${id} or [ ];
            include = id: { s = [ "t" ]; }.${id} or [ ];
            owni = id: { t = [ "x@t" ]; }.${id} or [ ];
          };
          # follow: own | include owni  (a declaration here, or one hop through an include)
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "own | include owni";
            mode = "visible";
            order.labels = [
              "own"
              "include"
              "owni"
            ];
            groupBy = _: "decl"; # both answers compete for one name
          };
        in
        {
          visible = map (a: a.node) res.visible;
          shadowed = map (a: a.node) res.shadowed;
        };
      expected = {
        visible = [ "x@s" ];
        shadowed = [ "x@t" ];
      };
    };
    test-visible-default-group-no-cross-shadow = {
      # default groupBy = node: distinct nodes both visible
      expr =
        let
          g = labeledFrom {
            own = id: { s = [ "a" ]; }.${id} or [ ];
            include = id: { s = [ "b" ]; }.${id} or [ ];
          };
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "own | include";
            mode = "visible";
            order.labels = [
              "own"
              "include"
            ];
          };
        in
        builtins.sort builtins.lessThan (map (a: a.node) res.visible);
      expected = [
        "a"
        "b"
      ];
    };
    test-visible-prefix-beats-extension = {
      # same group, one answer at depth 1 and one at depth 2 through equal-rank labels:
      # the shorter (more direct) wins
      expr =
        let
          g = labeledFrom {
            hop =
              id:
              {
                s = [ "n1" ];
                n1 = [ "n2" ];
              }
              .${id} or [ ];
          };
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "hop hop?";
            mode = "visible";
            order.labels = [ "hop" ];
            groupBy = _: "g";
          };
        in
        map (a: a.node) res.visible;
      expected = [ "n1" ];
    };
    test-layers-cascade-order = {
      # layers: own layer before include layer before parent layer
      expr =
        let
          g = labeledFrom {
            own = id: { s = [ "l-own" ]; }.${id} or [ ];
            include = id: { s = [ "l-inc" ]; }.${id} or [ ];
            parent = id: { s = [ "l-par" ]; }.${id} or [ ];
          };
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "own | include | parent";
            mode = "layers";
            order.labels = [
              "own"
              "include"
              "parent"
            ];
          };
        in
        map (layer: map (a: a.node) layer) res;
      expected = [
        [ "l-own" ]
        [ "l-inc" ]
        [ "l-par" ]
      ];
    };
    test-visible-endofpath-continuation-wins = {
      # endOfPath ranked WORSE than the label: continuing beats stopping — n2 wins over n1
      expr =
        let
          g = labeledFrom {
            hop =
              id:
              {
                s = [ "n1" ];
                n1 = [ "n2" ];
              }
              .${id} or [ ];
          };
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "hop hop?";
            mode = "visible";
            order = {
              labels = [ "hop" ];
              endOfPath = 5;
            };
            groupBy = _: "g";
          };
        in
        map (a: a.node) res.visible;
      expected = [ "n2" ];
    };
    test-visible-unlisted-label-ranks-last = {
      expr =
        let
          g = labeledFrom {
            own = id: { s = [ "near" ]; }.${id} or [ ];
            exotic = id: { s = [ "far" ]; }.${id} or [ ];
          };
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "own | exotic";
            mode = "visible";
            order.labels = [ "own" ];
            groupBy = _: "g";
          };
        in
        map (a: a.node) res.visible;
      expected = [ "near" ];
    };
    test-visible-empty-answers = {
      # degenerate: no reachable answers — {[];[]} without a head-of-empty throw
      # (the guard is groupBy dropping empty groups; pin the invariant)
      expr = query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.parse "contains";
        mode = "visible";
        where = _: false;
      };
      expected = {
        visible = [ ];
        shadowed = [ ];
      };
    };
    test-visible-eop-tie-covisible = {
      # endOfPath rank EQUAL to a label rank: incomparable-as-equal — both answers visible
      expr =
        let
          g = labeledFrom {
            hop =
              id:
              {
                s = [ "n1" ];
                n1 = [ "n2" ];
              }
              .${id} or [ ];
          };
          res = query {
            graph = g;
            from = "s";
            follow = r.parse "hop hop?";
            mode = "visible";
            order = {
              labels = [ "hop" ];
              endOfPath = 0;
            };
            groupBy = _: "g";
          };
        in
        map (a: a.node) res.visible;
      expected = [
        "n1"
        "n2"
      ];
    };
    test-fold-group-closure = {
      # groups include groups; effective members = fold over member closure
      expr =
        let
          g = labeledFrom {
            includes = id: { admins = [ "wheel" ]; }.${id} or [ ];
            member =
              id:
              {
                admins = [ "sini" ];
                wheel = [ "root-u" ];
              }
              .${id} or [ ];
          };
        in
        genGraph.queryFold {
          graph = g;
          from = "admins";
          follow = r.parse "includes* member";
          empty = [ ];
          combine = acc: u: acc ++ [ u ];
        };
      expected = [
        "root-u"
        "sini"
      ];
    };
    test-fold-empty-answers = {
      expr = genGraph.queryFold {
        graph = labeledFixtures.world;
        from = "u2";
        follow = r.parse "member";
        empty = 0;
        combine = a: _: a + 1;
      };
      expected = 0;
    };
    test-fixpoint-mode-aliases-fold = {
      # the spec-surface mode string dispatches to the same fold
      expr =
        let
          common = {
            graph = labeledFixtures.world;
            from = "g1";
            follow = r.parse "member";
            empty = 0;
            combine = a: _: a + 1;
          };
        in
        query (common // { mode = "fixpoint"; }) == genGraph.queryFold common;
      expected = true;
    };
  };
}
