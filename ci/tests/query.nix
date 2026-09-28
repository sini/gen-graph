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
  didThrow = v: !(builtins.tryEval (builtins.deepSeq v true)).success;
in
{
  flake.tests.query = {
    test-all-contains-closure = {
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.world;
            from = "root";
            follow = r.star (r.lit "contains");
          }
      );
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
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.world;
            from = "root";
            follow = r.plus (r.lit "contains");
          }
      );
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
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.world;
            from = "root";
            follow = r.parse "contains contains";
          }
      );
      expected = [
        "u1"
        "vm1"
      ];
    };
    test-all-mixed-labels = {
      # member include? from g1 → members and what they include
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.world;
            from = "g1";
            follow = r.parse "member include?";
          }
      );
      expected = [
        "shared"
        "u1"
        "u2"
      ];
    };
    test-all-where-filters = {
      expr =
        query
          {
            mode = "all";
            where = id: id == "vm1";
          }
          {
            graph = labeledFixtures.world;
            from = "root";
            follow = r.parse "contains*";
          };
      expected = [ "vm1" ];
    };
    test-all-cycle-terminates = {
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.cyclic;
            from = "a";
            follow = r.parse "contains* member";
          }
      );
      expected = [ "m" ];
    };
    test-all-wrong-label-blocked = {
      expr =
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.world;
            from = "g1";
            follow = r.parse "contains";
          };
      expected = [ ];
    };
    test-labeled-from-adapter = {
      # per-label plain accessors (the gen-scope followEdge shape) → labeledEdges
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph =
              labeledFrom
                {
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
                }
                [
                  "g1"
                  "h1"
                  "h2"
                  "root"
                  "u1"
                ];
            from = "root";
            follow = r.parse "contains+";
          }
      );
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
              # the lift is total in both halves: the plain fixture's own node set is
              # what the labeled contract requires, so nothing is invented here.
              lifted = labeledFrom {
                edge = id: fx.edges id;
              } fx.nodes;
              viaQuery = builtins.filter (x: x != from) (
                query
                  {
                    mode = "all";
                  }
                  {
                    graph = lifted;
                    inherit from;
                    follow = r.star r.any;
                  }
              );
            in
            sorted viaQuery == sorted (reachableFrom fx from);
        in
        check fixtures.diamond "a" && check fixtures.cyclic "a";
      expected = true;
    };
    test-laziness-poison-unreached = {
      expr =
        query
          {
            mode = "all";
          }
          {
            graph = labeledFixtures.poisoned;
            from = "a";
            follow = r.parse "safe";
          };
      expected = [ "b" ];
    };
    test-all-dedup-across-nullable-states = {
      # n reached in TWO distinct nullable derivative states (residuals e and (e|'z));
      # answers are a SET — one entry. Also covers parallel same-target edges.
      expr =
        query
          {
            mode = "all";
          }
          {
            graph =
              labeledFrom
                {
                  x = id: { s = [ "n" ]; }.${id} or [ ];
                  y = id: { s = [ "n" ]; }.${id} or [ ];
                }
                [
                  "n"
                  "s"
                ];
            from = "s";
            follow = r.parse "x | y z?";
          };
      expected = [ "n" ];
    };
    test-paths-witness-shape = {
      expr =
        query
          {
            mode = "paths";
          }
          {
            graph = labeledFixtures.world;
            from = "g1";
            follow = r.parse "member include";
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
          g =
            labeledFrom
              {
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
              }
              [
                "a"
                "b"
                "c"
                "d"
              ];
          res =
            query
              {
                mode = "paths";
              }
              {
                graph = g;
                from = "a";
                follow = r.parse "e e";
              };
        in
        builtins.length (builtins.filter (ans: ans.node == "d") res);
      expected = 2;
    };
    test-paths-cycle-terminates = {
      expr = builtins.length (
        query
          {
            mode = "paths";
          }
          {
            graph = labeledFixtures.cyclic;
            from = "a";
            follow = r.parse "contains* member";
          }
      );
      expected = 1;
    };
    test-paths-nullable-start = {
      expr = builtins.head (
        query
          {
            mode = "paths";
            where = id: id == "root";
          }
          {
            graph = labeledFixtures.world;
            from = "root";
            follow = r.parse "contains*";
          }
      );
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
          g = labeledFrom {
            hop = id: { s = [ "s" ]; }.${id} or [ ];
          } [ "s" ];
          common = {
            graph = g;
            from = "s";
            follow = r.parse "hop";
          };
        in
        {
          all = query { mode = "all"; } common;
          paths = query { mode = "paths"; } common;
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
          g =
            labeledFrom
              {
                own = id: { s = [ "x@s" ]; }.${id} or [ ];
                include = id: { s = [ "t" ]; }.${id} or [ ];
                owni = id: { t = [ "x@t" ]; }.${id} or [ ];
              }
              [
                "s"
                "t"
                "x@s"
                "x@t"
              ];
          # follow: own | include owni  (a declaration here, or one hop through an include)
          res =
            query
              {
                mode = "visible";
                order.labels = [
                  "own"
                  "include"
                  "owni"
                ];
                groupBy = _: "decl"; # both answers compete for one name
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "own | include owni";
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
    test-visible-per-node-group-no-cross-shadow = {
      # per-node groupBy (den-hoag-l7af: no longer the default — stated explicitly):
      # distinct nodes both visible
      expr =
        let
          g =
            labeledFrom
              {
                own = id: { s = [ "a" ]; }.${id} or [ ];
                include = id: { s = [ "b" ]; }.${id} or [ ];
              }
              [
                "a"
                "b"
                "s"
              ];
          res =
            query
              {
                mode = "visible";
                order.labels = [
                  "own"
                  "include"
                ];
                groupBy = ans: ans.node;
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "own | include";
              };
        in
        builtins.sort builtins.lessThan (map (a: a.node) res.visible);
      expected = [
        "a"
        "b"
      ];
    };
    # SEEDED RED (den-hoag-l7af / ADR-0024 ruling 3): `groupBy` omitted entirely used to
    # default to per-node, silently returning the gather-all answer with `shadowed = []`
    # under a mode named for the shadowing split. It must now refuse, naming the missing
    # argument, rather than answer a competition question the caller never asked.
    test-visible-refuses-missing-groupby = {
      expr = didThrow (
        query
          {
            mode = "visible";
            order.labels = [ "parent" ];
          }
          {
            graph =
              labeledFrom
                {
                  parent =
                    id:
                    {
                      s = [ "mid" ];
                      mid = [ "root" ];
                    }
                    .${id} or [ ];
                }
                [
                  "s"
                  "mid"
                  "root"
                ];
            from = "s";
            follow = r.star (r.lit "parent");
          }
      );
      expected = true;
    };
    # LIVE CONTROL: the same query WITH `groupBy` supplied is not caught, so the refusal
    # above discriminates rather than always firing.
    test-visible-groupby-supplied-control = {
      expr = didThrow (
        query
          {
            mode = "visible";
            order.labels = [ "parent" ];
            groupBy = ans: ans.node;
          }
          {
            graph =
              labeledFrom
                {
                  parent =
                    id:
                    {
                      s = [ "mid" ];
                      mid = [ "root" ];
                    }
                    .${id} or [ ];
                }
                [
                  "s"
                  "mid"
                  "root"
                ];
            from = "s";
            follow = r.star (r.lit "parent");
          }
      );
      expected = false;
    };
    test-visible-prefix-beats-extension = {
      # same group, one answer at depth 1 and one at depth 2 through equal-rank labels:
      # the shorter (more direct) wins
      expr =
        let
          g =
            labeledFrom
              {
                hop =
                  id:
                  {
                    s = [ "n1" ];
                    n1 = [ "n2" ];
                  }
                  .${id} or [ ];
              }
              [
                "n1"
                "n2"
                "s"
              ];
          res =
            query
              {
                mode = "visible";
                order.labels = [ "hop" ];
                groupBy = _: "g";
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "hop hop?";
              };
        in
        map (a: a.node) res.visible;
      expected = [ "n1" ];
    };
    test-layers-cascade-order = {
      # layers: own layer before include layer before parent layer
      expr =
        let
          g =
            labeledFrom
              {
                own = id: { s = [ "l-own" ]; }.${id} or [ ];
                include = id: { s = [ "l-inc" ]; }.${id} or [ ];
                parent = id: { s = [ "l-par" ]; }.${id} or [ ];
              }
              [
                "l-inc"
                "l-own"
                "l-par"
                "s"
              ];
          res =
            query
              {
                mode = "layers";
                order.labels = [
                  "own"
                  "include"
                  "parent"
                ];
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "own | include | parent";
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
          g =
            labeledFrom
              {
                hop =
                  id:
                  {
                    s = [ "n1" ];
                    n1 = [ "n2" ];
                  }
                  .${id} or [ ];
              }
              [
                "n1"
                "n2"
                "s"
              ];
          res =
            query
              {
                mode = "visible";
                order = {
                  labels = [ "hop" ];
                  endOfPath = 5;
                };
                groupBy = _: "g";
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "hop hop?";
              };
        in
        map (a: a.node) res.visible;
      expected = [ "n2" ];
    };
    test-visible-unlisted-label-ranks-last = {
      expr =
        let
          g =
            labeledFrom
              {
                own = id: { s = [ "near" ]; }.${id} or [ ];
                exotic = id: { s = [ "far" ]; }.${id} or [ ];
              }
              [
                "far"
                "near"
                "s"
              ];
          res =
            query
              {
                mode = "visible";
                order.labels = [ "own" ];
                groupBy = _: "g";
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "own | exotic";
              };
        in
        map (a: a.node) res.visible;
      expected = [ "near" ];
    };
    test-visible-empty-answers = {
      # degenerate: no reachable answers — {[];[]} without a head-of-empty throw
      # (the guard is groupBy dropping empty groups; pin the invariant)
      expr =
        query
          {
            mode = "visible";
            where = _: false;
            groupBy = ans: ans.node;
          }
          {
            graph = labeledFixtures.world;
            from = "root";
            follow = r.parse "contains";
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
          g =
            labeledFrom
              {
                hop =
                  id:
                  {
                    s = [ "n1" ];
                    n1 = [ "n2" ];
                  }
                  .${id} or [ ];
              }
              [
                "n1"
                "n2"
                "s"
              ];
          res =
            query
              {
                mode = "visible";
                order = {
                  labels = [ "hop" ];
                  endOfPath = 0;
                };
                groupBy = _: "g";
              }
              {
                graph = g;
                from = "s";
                follow = r.parse "hop hop?";
              };
        in
        map (a: a.node) res.visible;
      expected = [
        "n1"
        "n2"
      ];
    };
    test-fold-group-closure = {
      # groups include groups; effective members = fold over member closure.
      # The list-append combine is deliberately NON-ACI: it pins the canonical
      # sorted-node fold order (a change to that order would flip this list).
      expr =
        let
          g =
            labeledFrom
              {
                includes = id: { admins = [ "wheel" ]; }.${id} or [ ];
                member =
                  id:
                  {
                    admins = [ "sini" ];
                    wheel = [ "root-u" ];
                  }
                  .${id} or [ ];
              }
              [
                "admins"
                "root-u"
                "sini"
                "wheel"
              ];
        in
        genGraph.queryFold { } (acc: u: acc ++ [ u ]) [ ] {
          graph = g;
          from = "admins";
          follow = r.parse "includes* member";
        };
      expected = [
        "root-u"
        "sini"
      ];
    };
    test-fold-where-valueOf = {
      # where + valueOf flow THROUGH queryFold to the closure (the strip-list
      # deliberately omits them) — where filters the folded set, valueOf maps it
      expr =
        let
          g =
            labeledFrom
              {
                includes = id: { admins = [ "wheel" ]; }.${id} or [ ];
                member =
                  id:
                  {
                    admins = [ "sini" ];
                    wheel = [ "root-u" ];
                  }
                  .${id} or [ ];
              }
              [
                "admins"
                "root-u"
                "sini"
                "wheel"
              ];
        in
        genGraph.queryFold
          {
            where = id: id != "sini";
            valueOf = builtins.stringLength;
          }
          (a: n: a + n)
          0
          {
            graph = g;
            from = "admins";
            follow = r.parse "includes* member";
          };
      expected = 6; # "root-u" only
    };
    test-fold-empty-answers = {
      expr = genGraph.queryFold { } (a: _: a + 1) 0 {
        graph = labeledFixtures.world;
        from = "u2";
        follow = r.parse "member";
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
          };
          empty = 0;
          combine = a: _: a + 1;
        in
        query {
          mode = "fixpoint";
          inherit empty combine;
        } common == genGraph.queryFold { } combine empty common;
      expected = true;
    };
  };
}
