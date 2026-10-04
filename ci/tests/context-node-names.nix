# Context-carrying node names: a node, scope, key or label whose name is a string WITH store
# context (`baseNameOf pkgs.hello` is one) is KEYED by its text, so every walk completes where it
# used to abort uncatchably, and the caller's value keeps its context (den-hoag-u9k7j).
#
# `x` below is the text "x" carrying a store-path context. Every accessor the fixtures hand the
# library decides membership by `==` (`at`), never by keying the id itself, so an abort here is the
# library's and never the fixture's.
{ genGraph, ... }:
let
  inherit (genGraph)
    ancestorsOf
    pathsBetween
    hoistEdges
    cycles
    dependentsOf
    dependentsFrontier
    directDependentsOf
    transpose
    dependents
    condensationClosure
    cyclePaths
    roots
    materialize
    materializeParents
    intersectEdges
    differenceEdges
    compose
    transitiveClosure
    transitiveReduction
    fromRegistry
    field
    mkGraph
    fromScan
    mkDeclaredEdges
    mkSpawnedNodeRef
    topoOrder
    topoOrderKahn
    coneRank
    phaseOrder
    entryAfter
    entryBefore
    entryAnywhere
    condensationOf
    condensation
    fbWork
    labeledTranspose
    cyclicEdgesWhere
    foldPreorder
    foldReach
    labeledFixtures
    ;
  store = builtins.toFile "gen-graph-context-node-names" "x";
  ctx = s: "${builtins.substring 0 0 (toString store)}${s}";
  x = ctx "x";
  kv = k: v: { inherit k v; };
  at =
    tbl: dflt: id:
    let
      hit = builtins.filter (p: p.k == id) tbl;
    in
    if hit == [ ] then dflt else (builtins.head hit).v;
  edgesCyc =
    at
      [
        (kv "a" [ x ])
        (kv "x" [ "b" ])
        (kv "b" [ x ])
      ]
      [ ];
  edgesDag =
    at
      [
        (kv "a" [ x ])
        (kv "x" [ "b" ])
      ]
      [ ];
  gCyc = {
    nodes = [
      "a"
      x
      "b"
    ];
    edges = edgesCyc;
  };
  gDag = {
    nodes = [
      "a"
      x
      "b"
    ];
    edges = edgesDag;
  };
  gDagPlainNodes = {
    nodes = [
      "a"
      "x"
      "b"
    ];
    edges = edgesDag;
  };
  gTwin = {
    nodes = [
      "a"
      "x"
      "b"
    ];
    edges =
      at
        [
          (kv "a" [ "x" ])
          (kv "x" [ "b" ])
        ]
        [ ];
  };
  # m (context) <-> z: `m` is the minimum member, so it is the component's representative.
  gMin =
    let
      m = ctx "m";
    in
    {
      nodes = [
        m
        "z"
      ];
      edges =
        at
          [
            (kv "m" [ "z" ])
            (kv "z" [ m ])
          ]
          [ ];
    };
  # A DAG whose context-carrying node is LAST in `nodes` and alone has out-degree 2. `sort` hands a
  # node to its comparator as `b` or `a` by position, so only a node that arrives late is ever read
  # through the comparator's `a` side.
  gLast =
    let
      m = ctx "m";
    in
    {
      nodes = [
        "a"
        "b"
        "q"
        m
      ];
      edges =
        at
          [
            (kv "m" [
              "a"
              "b"
            ])
            (kv "a" [ "b" ])
          ]
          [ ];
    };
  # four context-carrying producers of one consumer: the Kahn step's succs/residue/removeAttrs path.
  gFan = {
    nodes = [
      "m"
      (ctx "p")
      (ctx "q")
      (ctx "r")
      (ctx "s")
    ];
    edges =
      at
        [
          (kv "m" [
            (ctx "p")
            (ctx "q")
            (ctx "r")
            (ctx "s")
          ])
        ]
        [ ];
  };
  # A labeled record written as data (den-hoag-gayc U3), labels in name order.
  labOf =
    nodes: t: perLabelIncludeB:
    let
      perLabel = {
        include = at ([ (kv "x" [ "b" ]) ] ++ perLabelIncludeB) [ ];
        parent = at [ (kv "a" [ t ]) ] [ ];
      };
    in
    {
      inherit nodes;
      labeledEdges =
        id:
        builtins.concatMap (
          label:
          map (target: {
            inherit label target;
          }) (perLabel.${label} id)
        ) (builtins.attrNames perLabel);
    };
  lab = labOf [ "a" x "b" ] x [ ];
  labCyc = labOf [ "a" x "b" ] x [ (kv "b" [ x ]) ];
in
{
  flake.tests.context-node-names = {
    # T1
    test-ancestors-through-a-context-carrying-parent = {
      expr = ancestorsOf { } {
        parent = at [ (kv "a" x) (kv "x" "b") ] null;
      } "a";
      expected = [
        "x"
        "b"
      ];
    };
    # T1
    test-ancestors-from-a-context-carrying-start = {
      expr = ancestorsOf { } {
        parent = at [ (kv "x" "b") ] null;
      } x;
      expected = [ "b" ];
    };
    # T2
    test-paths-between-through-a-context-carrying-node = {
      expr = pathsBetween { } gDag "a" "b";
      expected = [
        [
          "a"
          "x"
          "b"
        ]
      ];
    };
    # T3
    test-hoisted-edges-over-a-context-carrying-node-set = {
      expr = map (i: i.key) (hoistEdges gCyc "a");
      expected = [ "x" ];
    };
    # T3
    test-hoisted-edges-looked-up-by-a-context-carrying-id = {
      expr = map (i: i.key) (hoistEdges gDagPlainNodes x);
      expected = [ "b" ];
    };
    # T3
    test-cycles-through-a-context-carrying-node = {
      expr = cycles gCyc;
      expected = [
        "b"
        "x"
      ];
    };
    # G1
    test-dependents-of-by-reverse-index = {
      expr = dependentsOf gDag "b";
      expected = [
        "a"
        "x"
      ];
    };
    # G1
    test-dependents-frontier-by-reverse-index = {
      expr = dependentsFrontier gDag "b" (_: true);
      expected = [
        "a"
        "x"
      ];
    };
    # G1
    test-direct-dependents-of-a-context-carrying-id = {
      expr = directDependentsOf gDag x;
      expected = [ "a" ];
    };
    # G2
    test-transpose-over-a-context-carrying-target = {
      expr = (transpose gDag).edges "b";
      expected = [ "x" ];
    };
    # G2
    test-transpose-looked-up-by-a-context-carrying-id = {
      expr = (transpose gDag).edges x;
      expected = [ "a" ];
    };
    # G2
    test-closure-dependents-of-a-context-carrying-target = {
      expr = dependents { } gDag x;
      expected = [ "a" ];
    };
    # G3
    test-condensation-closure-with-a-context-carrying-node = {
      expr = (condensationClosure { } gCyc).sccs;
      expected = [
        [
          "b"
          "x"
        ]
        [ "a" ]
      ];
    };
    # G4
    test-cycle-paths-through-a-context-carrying-node = {
      expr = cyclePaths gCyc;
      expected = [
        [
          "b"
          "x"
        ]
      ];
    };
    # E1
    test-roots-over-a-context-carrying-target = {
      expr = roots gDag;
      expected = [ "a" ];
    };
    # E1
    test-roots-over-a-context-carrying-node = {
      expr = roots {
        nodes = [
          "a"
          x
        ];
        edges = at [ (kv "a" [ ]) ] [ ];
      };
      expected = [
        "a"
        "x"
      ];
    };
    # M1
    test-materialize-a-context-carrying-node-set = {
      expr = materialize gDag;
      expected = {
        a = [ "x" ];
        b = [ ];
        x = [ "b" ];
      };
    };
    # M2
    test-materialize-parents-of-a-context-carrying-child = {
      expr = materializeParents {
        nodes = [
          "a"
          x
        ];
        parent = id: if id == "a" then null else "a";
      };
      expected = {
        x = "a";
      };
    };
    # M3
    test-intersect-edges-at-a-context-carrying-target = {
      expr = intersectEdges { a = [ x ]; } { a = [ x ]; };
      expected = {
        a = [ "x" ];
      };
    };
    # M3
    test-difference-edges-at-a-context-carrying-target = {
      expr = differenceEdges {
        minuend = {
          a = [
            x
            "b"
          ];
        };
        subtrahend = {
          a = [ x ];
        };
      };
      expected = {
        a = [ "b" ];
      };
    };
    # F1
    test-compose-through-a-context-carrying-midpoint = {
      expr = compose {
        first = {
          a = [ x ];
        };
        second = {
          x = [ "b" ];
        };
      };
      expected = {
        a = [ "b" ];
      };
    };
    # F2
    test-transitive-closure-through-a-context-carrying-node = {
      expr = transitiveClosure { } gDag;
      expected = {
        a = [
          "x"
          "b"
        ];
        x = [ "b" ];
      };
    };
    # F2
    test-transitive-reduction-through-a-context-carrying-node = {
      expr = transitiveReduction { } gDag;
      expected = {
        a = [ "x" ];
        x = [ "b" ];
      };
    };
    # R1
    test-registry-looked-up-by-a-context-carrying-id = {
      expr =
        (fromRegistry { } (field "deps") {
          x = {
            deps = [ "b" ];
          };
        }).edges
          x;
      expected = [ "b" ];
    };
    # R2 R3
    test-mkgraph-over-a-context-carrying-endpoint = {
      expr =
        let
          g = mkGraph {
            edges = [
              {
                from = "a";
                to = x;
              }
              {
                from = x;
                to = "b";
              }
            ];
          };
        in
        {
          n = g.nodes;
          e = g.edges x;
        };
      expected = {
        e = [ "b" ];
        n = [
          "a"
          "b"
          "x"
        ];
      };
    };
    # R2 R4
    test-mkgraph-parent-of-a-context-carrying-child = {
      expr =
        (mkGraph {
          parents = [
            {
              from = x;
              to = "a";
            }
          ];
        }).parent
          x;
      expected = "a";
    };
    # R5
    test-mkgraph-node-data-by-a-context-carrying-id = {
      expr =
        (mkGraph {
          nodeData = {
            x = {
              t = 1;
            };
          };
        }).nodeData
          x;
      expected = {
        t = 1;
      };
    };
    # R2
    test-scan-over-a-context-carrying-reference = {
      expr =
        (fromScan { } {
          items = [
            {
              id = "a";
              value = [ x ];
            }
          ];
          scan = v: v;
          project = r: r;
        }).nodes;
      expected = [
        "a"
        "x"
      ];
    };
    # D1
    test-declared-edges-from-a-spawned-context-carrying-ref = {
      expr =
        (mkDeclaredEdges [
          {
            from = mkSpawnedNodeRef x;
            to = mkSpawnedNodeRef "b";
          }
        ]).dependencies
          x;
      expected = [ "b" ];
    };
    # O1
    test-topo-order-over-a-context-carrying-node = {
      expr = topoOrder { } gDag;
      expected = {
        ok = true;
        order = [
          "b"
          "x"
          "a"
        ];
      };
    };
    # O1
    test-topo-order-names-a-cycle-through-a-context-carrying-node = {
      expr = topoOrder { } gCyc;
      expected = {
        cycles = [
          [
            "b"
            "x"
          ]
        ];
        ok = false;
      };
    };
    # O1
    test-kahn-order-over-a-context-carrying-node = {
      expr = topoOrderKahn { } gDag;
      expected = {
        ok = true;
        order = [
          "b"
          "x"
          "a"
        ];
      };
    };
    # O1
    test-kahn-order-over-a-wide-context-carrying-fan = {
      expr = topoOrderKahn { } gFan;
      expected = {
        ok = true;
        order = [
          "p"
          "q"
          "r"
          "s"
          "m"
        ];
      };
    };
    # O2
    test-cone-rank-over-a-context-carrying-node = {
      expr =
        (coneRank gDag [
          "a"
          x
          "b"
        ]).order;
      expected = [
        "b"
        "x"
        "a"
      ];
    };
    # O3
    test-phase-order-with-a-context-carrying-reference = {
      expr = phaseOrder {
        a = entryAfter [ x ];
        x = entryAnywhere;
      };
      expected = [
        "x"
        "a"
      ];
    };
    # O3
    test-phase-order-with-a-context-carrying-before = {
      expr = phaseOrder {
        a = entryBefore [ x ];
        x = entryAnywhere;
      };
      expected = [
        "a"
        "x"
      ];
    };
    # P1
    test-condensation-of-context-carrying-tags = {
      expr =
        (condensationOf gDag {
          a = "a";
          x = x;
          b = "b";
        }).sccs;
      expected = [
        [ "b" ]
        [ "x" ]
        [ "a" ]
      ];
    };
    # P2
    test-condensation-through-a-context-carrying-node = {
      expr = (condensation gCyc).sccs;
      expected = [
        [
          "b"
          "x"
        ]
        [ "a" ]
      ];
    };
    # P3
    test-work-partition-through-a-context-carrying-node = {
      expr = (fbWork gCyc).sccs;
      expected = [
        [
          "b"
          "x"
        ]
        [ "a" ]
      ];
    };
    # Q1
    test-labeled-transpose-over-a-context-carrying-target = {
      expr = map (e: e.target) ((labeledTranspose lab).labeledEdges "b");
      expected = [ "x" ];
    };
    # Q1
    test-labeled-transpose-looked-up-by-a-context-carrying-id = {
      expr = map (e: e.target) ((labeledTranspose lab).labeledEdges x);
      expected = [ "a" ];
    };
    # Q3
    test-cyclic-edges-where-through-a-context-carrying-node = {
      expr = cyclicEdgesWhere (_: true) labCyc;
      expected = [
        {
          from = "b";
          label = "include";
          to = "x";
        }
        {
          from = "x";
          label = "include";
          to = "b";
        }
      ];
    };
    # Pr1
    test-fold-preorder-keyed-by-a-context-carrying-node = {
      expr =
        (foldPreorder { } {
          roots = [ "a" ];
          key = k: k;
          expand = acc: f: {
            acc = acc ++ [ f ];
            children = edgesDag f;
          };
          acc = [ ];
        }).acc;
      expected = [
        "a"
        "x"
        "b"
      ];
    };
    # Pr2
    test-fold-reach-seen-by-a-context-carrying-item = {
      expr =
        (foldReach { } {
          roots = [ { t = "a"; } ];
          edges = id: map (t: { inherit t; }) (edgesDag id);
          target = e: e.t;
          project = e: [ e.t ];
          itemKey = i: i;
        }).nodes;
      expected = [
        "a"
        "x"
        "b"
      ];
    };
    # T2
    test-paths-between-past-a-context-carrying-node = {
      expr = pathsBetween { } {
        edges =
          at
            [
              (kv "a" [ x ])
              (kv "x" [ "c" ])
              (kv "c" [ "b" ])
            ]
            [ ];
      } "a" "b";
      expected = [
        [
          "a"
          "x"
          "c"
          "b"
        ]
      ];
    };
    # F2
    test-transitive-reduction-drops-an-edge-implied-through-a-context-carrying-node = {
      expr = transitiveReduction { } {
        nodes = [
          "a"
          x
          "b"
        ];
        edges =
          at
            [
              (kv "a" [
                x
                "b"
              ])
              (kv "x" [ "b" ])
            ]
            [ ];
      };
      expected = {
        a = [ "x" ];
        x = [ "b" ];
      };
    };
    # R1
    test-registry-parent-by-a-context-carrying-id = {
      expr =
        (fromRegistry
          {
            parent = _: e: e.up or null;
          }
          (field "deps")
          {
            x = {
              up = "a";
            };
          }
        ).parent
          x;
      expected = "a";
    };
    # R1
    test-registry-node-data-by-a-context-carrying-id = {
      expr =
        (fromRegistry { } (field "deps") {
          x = {
            t = 1;
          };
        }).nodeData
          x;
      expected = {
        t = 1;
      };
    };
    # R2
    test-mkgraph-nodes-from-context-carrying-parents = {
      expr =
        (mkGraph {
          parents = [
            {
              from = x;
              to = ctx "r";
            }
          ];
        }).nodes;
      expected = [
        "r"
        "x"
      ];
    };
    # R2
    test-mkgraph-nodes-from-node-data = {
      expr =
        (mkGraph {
          nodeData = {
            n = { };
          };
        }).nodes;
      expected = [ "n" ];
    };
    # O1
    test-topo-order-certifies-a-linked-context-carrying-candidate = {
      expr = topoOrder { } {
        nodes = [
          x
          "b"
        ];
        edges = at [ (kv "x" [ "b" ]) ] [ ];
      };
      expected = {
        ok = true;
        order = [
          "b"
          "x"
        ];
      };
    };
    # O1
    test-kahn-order-joins-at-a-context-carrying-consumer = {
      expr = topoOrderKahn { } {
        nodes = [
          "p"
          "q"
          (ctx "y")
        ];
        edges =
          at
            [
              (kv "y" [
                "p"
                "q"
              ])
            ]
            [ ];
      };
      expected = {
        ok = true;
        order = [
          "p"
          "q"
          "y"
        ];
      };
    };
    # P3
    test-work-partition-of-a-two-cycle-through-a-context-carrying-node = {
      expr =
        (fbWork {
          nodes = [
            "a"
            x
          ];
          edges =
            at
              [
                (kv "a" [ x ])
                (kv "x" [ "a" ])
              ]
              [ ];
        }).sccs;
      expected = [
        [
          "a"
          "x"
        ]
      ];
    };
    # F2
    test-transitive-reduction-through-a-midpoint-reaching-a-context-carrying-node = {
      expr = transitiveReduction { } {
        nodes = [
          "a"
          "m"
          x
        ];
        edges =
          at
            [
              (kv "a" [
                "m"
                x
              ])
              (kv "m" [ x ])
            ]
            [ ];
      };
      expected = {
        a = [ "m" ];
        m = [ "x" ];
      };
    };
    # R6
    test-fixture-world-looked-up-by-a-context-carrying-id = {
      expr = labeledFixtures.world.labeledEdges (ctx "u1");
      expected = [
        {
          label = "include";
          target = "shared";
        }
      ];
    };
    # R6
    test-fixture-cyclic-looked-up-by-a-context-carrying-id = {
      expr = labeledFixtures.cyclic.labeledEdges (ctx "b");
      expected = [
        {
          label = "contains";
          target = "a";
        }
      ];
    };
    # R6
    test-fixture-poisoned-looked-up-by-a-context-carrying-id = {
      expr = labeledFixtures.poisoned.labeledEdges (ctx "b");
      expected = [ ];
    };
    # R2 value
    test-a-registered-node-keeps-its-context = {
      expr =
        builtins.any builtins.hasContext
          (mkGraph {
            edges = [
              {
                from = "a";
                to = x;
              }
            ];
          }).nodes;
      expected = true;
    };
    # P1 value
    test-a-representative-keeps-its-context = {
      expr =
        let
          c = condensation gMin;
        in
        {
          reps = builtins.any builtins.hasContext c.reps;
          sccOf = builtins.hasContext c.sccOf.z;
        };
      expected = {
        reps = true;
        sccOf = true;
      };
    };
    # O1 value
    test-an-ordered-node-keeps-its-context = {
      expr = builtins.any builtins.hasContext (topoOrder { } gDag).order;
      expected = true;
    };
    # G4: the cycle's rotation starts at its smallest member, and that member carries context
    test-cycle-paths-rotated-to-a-context-carrying-smallest-member = {
      expr = cyclePaths gMin;
      expected = [
        [
          "m"
          "z"
        ]
      ];
    };
    # O1: the named cycle's smallest member carries context
    test-topo-order-names-a-cycle-whose-smallest-member-carries-context = {
      expr = topoOrder { } gMin;
      expected = {
        cycles = [
          [
            "m"
            "z"
          ]
        ];
        ok = false;
      };
    };
    # O1: the context node is last in `nodes` with a unique out-degree. `q` is free, so the graph
    # has more than one order and the door's pick among them is not the subject (clause 3): the
    # cell asserts membership and producers-first on the three edges.
    test-topo-order-over-a-context-carrying-node-listed-last = {
      expr =
        let
          r = topoOrder { } gLast;
          prefixBefore =
            k: xs:
            if xs == [ ] || builtins.head xs == k then
              [ ]
            else
              [ (builtins.head xs) ] ++ prefixBefore k (builtins.tail xs);
          before = a: b: builtins.elem a (prefixBefore b r.order);
        in
        {
          inherit (r) ok;
          members = builtins.sort builtins.lessThan r.order;
          producersFirst = before "b" "a" && before "a" "m" && before "b" "m";
        };
      expected = {
        ok = true;
        members = [
          "a"
          "b"
          "m"
          "q"
        ];
        producersFirst = true;
      };
    };
    # Q2's departure, pinned: an edge map holds a source only as an attribute name, so `dependents`
    # (read off the transposed closure's keys) returns text, while `dependentsOf` (read off the
    # reverse index, which carries the original) keeps the context. A fix to either reads here.
    test-dependents-of-keeps-context-where-dependents-returns-text = {
      expr = {
        dependentsOf = builtins.any builtins.hasContext (dependentsOf gDag "b");
        dependents = builtins.any builtins.hasContext (dependents { } gDag "b");
      };
      expected = {
        dependentsOf = true;
        dependents = false;
      };
    };
    # control
    test-control-the-fixture-name-carries-context = {
      expr = builtins.hasContext x;
      expected = true;
    };
    # control
    test-control-the-context-free-twin-answers-the-same = {
      expr = {
        t = topoOrder { } gTwin;
      };
      expected = {
        t = {
          ok = true;
          order = [
            "b"
            "x"
            "a"
          ];
        };
      };
    };
  };
}
