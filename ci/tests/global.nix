{ lib, genGraph, ... }:
let
  inherit (genGraph)
    cycles
    cyclePaths
    dependents
    dependentsOf
    dependentsFrontier
    transpose
    impactOf
    condensation
    coScc
    ;
  inherit (genGraph) fixtures mkGraph;
in
{
  flake.tests.global = {
    test-cycles-acyclic = {
      expr = cycles fixtures.chain;
      expected = [ ];
    };
    test-cycles-cyclic = {
      expr = cycles fixtures.cyclic;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-cycles-partial = {
      expr = cycles (mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "c";
          }
          {
            from = "c";
            to = "b";
          }
        ];
      });
      expected = [
        "b"
        "c"
      ];
    };
    test-cycles-self-loop = {
      expr = cycles (mkGraph {
        edges = [
          {
            from = "a";
            to = "a";
          }
        ];
      });
      expected = [ "a" ];
    };
    # --- cyclePaths (ordered representative cycle per component) ---

    # The control that must be present in every run: every other assertion below is a
    # non-emptiness claim, so an acyclic graph reporting [ ] is what makes them meaningful.
    test-cyclePaths-acyclic = {
      expr = cyclePaths fixtures.chain;
      expected = [ ];
    };
    test-cyclePaths-self-loop = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a";
            to = "a";
          }
        ];
      });
      expected = [ [ "a" ] ];
    };
    test-cyclePaths-2-cycle = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "a";
          }
        ];
      });
      expected = [
        [
          "a"
          "b"
        ]
      ];
    };
    # ORDER is the point: traversal order and key order disagree here. b -> d -> c -> b, with
    # keys sorting b < c < d. A membership set would report [ b c d ]; the path is [ b d c ].
    test-cyclePaths-order-is-traversal-not-key-sort = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "b";
            to = "d";
          }
          {
            from = "d";
            to = "c";
          }
          {
            from = "c";
            to = "b";
          }
        ];
      });
      expected = [
        [
          "b"
          "d"
          "c"
        ]
      ];
    };
    # ...and the membership set for that same graph IS key-sorted — the live contrast that
    # shows the two surfaces answer different questions.
    test-cyclePaths-contrast-with-cycles-membership = {
      expr = cycles (mkGraph {
        edges = [
          {
            from = "b";
            to = "d";
          }
          {
            from = "d";
            to = "c";
          }
          {
            from = "c";
            to = "b";
          }
        ];
      });
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    # Disjoint components: one representative each, ordered by component tag.
    test-cyclePaths-disjoint-components = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "a";
          }
          {
            from = "x";
            to = "y";
          }
          {
            from = "y";
            to = "x";
          }
        ];
      });
      expected = [
        [
          "a"
          "b"
        ]
        [
          "x"
          "y"
        ]
      ];
    };
    # Figure-eight: ONE component holding two distinct simple cycles (a->b->a, a->c->a) yields
    # ONE representative. The component is canonical; the cycle through it is existential.
    test-cyclePaths-figure-eight-one-representative = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "a";
          }
          {
            from = "a";
            to = "c";
          }
          {
            from = "c";
            to = "a";
          }
        ];
      });
      expected = [
        [
          "a"
          "b"
        ]
      ];
    };
    # A cyclic component with an acyclic tail: only the component's nodes appear in the path.
    test-cyclePaths-excludes-acyclic-tail = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "c";
          }
          {
            from = "c";
            to = "a";
          }
          {
            from = "a";
            to = "d";
          }
          {
            from = "x";
            to = "a";
          }
        ];
      });
      expected = [
        [
          "a"
          "b"
          "c"
        ]
      ];
    };
    # Node keys are opaque strings: a key containing the ':' separator a consumer uses to build
    # a compound address (gen-settings keys nodes "id_hash:field") round-trips untouched, so
    # field-level granularity is a property of the KEY, not something this library coarsens.
    test-cyclePaths-compound-key-with-separator = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a1b2c3d4deadbeef:f";
            to = "f1f2f3f4f5f6f7f8:h";
          }
          {
            from = "f1f2f3f4f5f6f7f8:h";
            to = "e5f6a7b8cafef00d:g";
          }
          {
            from = "e5f6a7b8cafef00d:g";
            to = "a1b2c3d4deadbeef:f";
          }
        ];
      });
      expected = [
        [
          "a1b2c3d4deadbeef:f"
          "f1f2f3f4f5f6f7f8:h"
          "e5f6a7b8cafef00d:g"
        ]
      ];
    };
    # Field granularity, negatively: aspect-level mutual reference is NOT a cycle when the
    # fields differ. theme:f -> terminal:g and terminal:h -> theme:k share no field address.
    test-cyclePaths-field-granular-permissive = {
      expr = cyclePaths (mkGraph {
        edges = [
          {
            from = "a1b2c3d4deadbeef:f";
            to = "e5f6a7b8cafef00d:g";
          }
          {
            from = "e5f6a7b8cafef00d:h";
            to = "a1b2c3d4deadbeef:k";
          }
        ];
      });
      expected = [ ];
    };
    # Every consecutive pair in a reported path is a real edge (the property the " -> " join
    # in a consumer's diagnostic asserts), checked on the discriminating fixture.
    test-cyclePaths-consecutive-pairs-are-edges = {
      expr =
        let
          adj = {
            b = [ "d" ];
            d = [ "c" ];
            c = [ "b" ];
          };
          g = mkGraph {
            edges = [
              {
                from = "b";
                to = "d";
              }
              {
                from = "d";
                to = "c";
              }
              {
                from = "c";
                to = "b";
              }
            ];
          };
          path = builtins.head (cyclePaths g);
          closed = path ++ [ (builtins.head path) ];
          pairs = lib.lists.zipLists closed (builtins.tail closed);
        in
        builtins.all (p: builtins.elem p.snd (adj.${p.fst} or [ ])) pairs;
      expected = true;
    };

    test-dependents-db = {
      expr = builtins.sort builtins.lessThan (dependents fixtures.serviceGraph "db");
      expected = [
        "api"
        "web"
        "worker"
      ];
    };
    test-dependents-leaf = {
      expr = dependents fixtures.chain "a";
      expected = [ ];
    };
    test-dependents-equals-impact = {
      expr = impactOf fixtures.serviceGraph "db";
      expected = dependents fixtures.serviceGraph "db";
    };
    test-transpose-chain = {
      expr =
        let
          rev = transpose fixtures.chain;
        in
        builtins.sort builtins.lessThan (rev.edges "d");
      expected = [ "c" ];
    };
    test-transpose-preserves-nodes = {
      expr = builtins.sort builtins.lessThan (transpose fixtures.serviceGraph).nodes;
      expected = builtins.sort builtins.lessThan fixtures.serviceGraph.nodes;
    };
    test-transpose-root-becomes-leaf = {
      expr = (transpose fixtures.chain).edges "a";
      expected = [ ];
    };
    test-transpose-cyclic = {
      expr =
        let
          rev = transpose fixtures.cyclic;
        in
        builtins.sort builtins.lessThan (rev.edges "a");
      expected = [ "c" ];
    };
    test-cycles-self-loop-closure = {
      expr =
        let
          g = mkGraph {
            edges = [
              {
                from = "a";
                to = "a";
              }
            ];
          };
          closure = genGraph.transitiveClosure g;
        in
        closure."a" or [ ];
      expected = [ "a" ];
    };

    # --- dependentsOf (single-target reverse traversal) ---

    test-dependentsOf-db = {
      expr = builtins.sort builtins.lessThan (dependentsOf fixtures.serviceGraph "db");
      expected = [
        "api"
        "web"
        "worker"
      ];
    };
    test-dependentsOf-leaf = {
      expr = dependentsOf fixtures.chain "a";
      expected = [ ];
    };
    test-dependentsOf-matches-dependents = {
      expr = dependentsOf fixtures.serviceGraph "queue";
      expected = dependents fixtures.serviceGraph "queue";
    };
    test-impactOf-uses-dependentsOf = {
      expr = impactOf fixtures.serviceGraph "cache";
      expected = dependentsOf fixtures.serviceGraph "cache";
    };

    # --- dependentsFrontier ---
    test-frontier-prune-all-equals-dependentsOf = {
      # prune = _: true reduces EXACTLY to dependentsOf (the conformance anchor).
      expr = dependentsFrontier fixtures.serviceGraph "db" (_: true);
      expected = builtins.sort builtins.lessThan (dependentsOf fixtures.serviceGraph "db");
    };
    test-frontier-prune-false-at-target = {
      # prune targetId == false => seed0 == [] => nothing downstream walked.
      expr = dependentsFrontier fixtures.serviceGraph "db" (_: false);
      expected = [ ];
    };
    test-frontier-cutoff-mid-cone = {
      # db's reverse neighbours are {api, worker}; cutting api stops web; worker has no dependents.
      expr = dependentsFrontier fixtures.serviceGraph "db" (id: id != "api");
      expected = [
        "api"
        "worker"
      ];
    };
    test-frontier-pruned-boundary-present = {
      # the pruned node api is STILL in the output (reached); only web is cut.
      expr = builtins.elem "api" (dependentsFrontier fixtures.serviceGraph "db" (id: id != "api"));
      expected = true;
    };
    test-frontier-cyclic-terminates = {
      # cycle guard: prune-all on a cyclic graph terminates and equals dependentsOf.
      expr = dependentsFrontier fixtures.cyclic "a" (_: true);
      expected = builtins.sort builtins.lessThan (dependentsOf fixtures.cyclic "a");
    };
    test-frontier-prune-only-shrinks = {
      # property (concrete witness): any prune yields a subset of the prune-all cone.
      expr =
        let
          full = dependentsFrontier fixtures.serviceGraph "db" (_: true);
          cut = dependentsFrontier fixtures.serviceGraph "db" (id: id != "api");
        in
        builtins.all (id: builtins.elem id full) cut;
      expected = true;
    };

    # --- condensation + coScc ---
    test-condensation-acyclic-singletons-d-first = {
      # chain a->b->c->d: every node its own singleton, bottom-up (d first, producers first).
      expr = (condensation fixtures.chain).sccs;
      expected = [
        [ "d" ]
        [ "c" ]
        [ "b" ]
        [ "a" ]
      ];
    };
    test-condensation-cyclic-single-scc = {
      expr = (condensation fixtures.cyclic).sccs;
      expected = [
        [
          "a"
          "b"
          "c"
        ]
      ];
    };
    test-condensation-cyclic-tag-is-min-member = {
      expr =
        let
          c = condensation fixtures.cyclic;
        in
        [
          c.sccOf."a"
          c.sccOf."b"
          c.sccOf."c"
        ];
      expected = [
        "a"
        "a"
        "a"
      ];
    };
    test-coScc-acyclic-node-self = {
      # an acyclic node IS its own SCC (guards the closure-self-exclusion special case).
      expr = coScc fixtures.chain "b" "b";
      expected = true;
    };
    test-condensation-index-alignment = {
      # index alignment: reps == bottomUp AND sccs == the member lists read in reps order.
      expr =
        let
          c = condensation fixtures.chain;
        in
        (c.reps == c.bottomUp) && (map (r: c.members.${r}) c.reps == c.sccs);
      expected = true;
    };
    test-condensation-condEdges-direction = {
      # a->b->c->a cycle, a->d, x->a, y->x. condEdges(sccOf a)=[sccOf d]; condEdges(sccOf x)=[sccOf a].
      expr =
        let
          g = mkGraph {
            edges = [
              {
                from = "a";
                to = "b";
              }
              {
                from = "b";
                to = "c";
              }
              {
                from = "c";
                to = "a";
              }
              {
                from = "a";
                to = "d";
              }
              {
                from = "x";
                to = "a";
              }
              {
                from = "y";
                to = "x";
              }
            ];
          };
          c = condensation g;
        in
        [
          c.condEdges.${c.sccOf."a"}
          c.condEdges.${c.sccOf."x"}
        ];
      expected = [
        [ "d" ]
        [ "a" ]
      ];
    };
    test-condensation-ordering-soundness = {
      # property witness: every condEdges target appears strictly EARLIER in bottomUp.
      expr =
        let
          g = mkGraph {
            edges = [
              {
                from = "a";
                to = "b";
              }
              {
                from = "b";
                to = "c";
              }
              {
                from = "c";
                to = "a";
              }
              {
                from = "a";
                to = "d";
              }
              {
                from = "x";
                to = "a";
              }
              {
                from = "y";
                to = "x";
              }
            ];
          };
          c = condensation g;
          idx = t: lib.lists.findFirstIndex (r: r == t) (-1) c.bottomUp;
        in
        builtins.all (r: builtins.all (target: idx target < idx r) c.condEdges.${r}) c.bottomUp;
      expected = true;
    };
  };
}
