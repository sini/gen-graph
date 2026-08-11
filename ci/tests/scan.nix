# fromScan — the graph a reference scan derives (Mokhov et al., ICFP 2018 §3: the dependency
# structure is a function of the task description). The scan and the projection are the caller's,
# so these fixtures invent a reference vocabulary gen-graph has never heard of and check that none
# of it leaks into the derivation.
#
# Node ids here are COMPOUND `<identity>:<field>` addresses. That shape is pinned in this library,
# not only at a consumer, because "ids are opaque strings" is the property that lets a caller key
# nodes by a field address at all — a derivation that split on the separator would still pass every
# bare-name test.
#
# ★ CONTROLS. Most assertions below are non-emptiness claims — edges derived, a cycle found — and a
# run without their zero arms cannot tell a true zero from an instrument that never fired. So the
# acyclic arm (`cyclePaths` over a graph with no cycle) and the empty arm (no items at all) run on
# the same constructor in the same run as the arms that report non-empty.
{
  lib,
  genGraph,
  ...
}:
let
  inherit (genGraph) fromScan cyclePaths;

  # The caller's reference vocabulary: a record naming a target and carrying a payload the
  # projection ignores and the derived edge preserves.
  refTo = target: payload: { inherit target payload; };
  item = id: refs: {
    inherit id;
    value = {
      inherit refs;
    };
  };
  scan = v: v.refs;
  project = r: r.target;

  # Compound field addresses; they sort A < B < C, which is what makes the representative cycle
  # walk below predictable (the component's smallest key is the entry point).
  addrA = "a1b2c3d4:font";
  addrB = "e5f6a7b8:size";
  addrC = "f1f2f3f4:theme";

  # A -> B -> C, no cycle.
  acyclic = fromScan {
    items = [
      (item addrA [ (refTo addrB "hop-1") ])
      (item addrB [ (refTo addrC "hop-2") ])
      (item addrC [ ])
    ];
    inherit scan project;
    nodeData = {
      ${addrA} = {
        field = "font";
      };
      ${addrC} = {
        field = "theme";
      };
    };
  };

  # A -> B -> C -> A.
  cyclic = fromScan {
    items = [
      (item addrA [ (refTo addrB "hop-1") ])
      (item addrB [ (refTo addrC "hop-2") ])
      (item addrC [ (refTo addrA "hop-3") ])
    ];
    inherit scan project;
  };

  # An item the scan finds nothing in, which nothing references: edges alone cannot know it.
  itemOnly = fromScan {
    items = [ (item addrA [ ]) ];
    inherit scan project;
  };
  seeded = fromScan {
    items = [ (item addrA [ ]) ];
    inherit scan project;
    nodeData = {
      ${addrA} = {
        field = "font";
      };
    };
  };

  # Two references from one item to the same target: the derivation keeps both hops, the accessor
  # reports one successor.
  parallel = fromScan {
    items = [
      (item addrA [
        (refTo addrB "hop-1")
        (refTo addrB "hop-2")
      ])
    ];
    inherit scan project;
  };

  empty = fromScan {
    items = [ ];
    inherit scan project;
  };

  # A derived graph still has a containment dimension. `parents` rides through to mkGraph beside
  # the derived edges; gen-schema's kind topology is the live case, unioning a parent edge set
  # with the ref edges a scan derives. A constructor that dropped it would push that caller back
  # to mkGraph and out of the derivation entirely.
  parented = fromScan {
    items = [ (item addrA [ (refTo addrB "hop-1") ]) ];
    inherit scan project;
    parents = [
      {
        from = addrA;
        to = addrC;
      }
    ];
  };

  # A parent edge that CONTRADICTS a derived one: the scan derives addrA -> addrB, the caller
  # declares addrB's parent to be addrA. The two indices are disjoint in mkGraph, so neither can
  # answer for the other — and in particular a parent cannot close a cycle in the derived graph.
  parentAgainstEdge = fromScan {
    items = [ (item addrA [ (refTo addrB "hop-1") ]) ];
    inherit scan project;
    parents = [
      {
        from = addrB;
        to = addrA;
      }
    ];
  };
  # The positive control for that last claim: the SAME shape with the back-hop DERIVED rather than
  # declared is a real cycle, so a `[ ]` above is the parent index staying out of it, not
  # cyclePaths failing to fire.
  derivedBackEdge = fromScan {
    items = [
      (item addrA [ (refTo addrB "hop-1") ])
      (item addrB [ (refTo addrA "hop-2") ])
    ];
    inherit scan project;
  };

  throws = e: !(builtins.tryEval (builtins.deepSeq e true)).success;

  keyPairs = g: map (e: { inherit (e) from to; }) g.derivedEdges;
in
{
  flake.tests.scan = {
    # ── the derivation ──
    test-edges-derived-from-scan = {
      expr = keyPairs acyclic;
      expected = [
        {
          from = addrA;
          to = addrB;
        }
        {
          from = addrB;
          to = addrC;
        }
      ];
    };
    # The reference's own payload survives on the edge, so a caller never scans twice.
    test-derived-edge-carries-the-reference = {
      expr = map (e: e.ref.payload) acyclic.derivedEdges;
      expected = [
        "hop-1"
        "hop-2"
      ];
    };
    # ...and so does the item it came from, which is the edge's source in full.
    test-derived-edge-carries-the-item = {
      expr = (lib.head acyclic.derivedEdges).item.id;
      expected = addrA;
    };

    # ── the node set ──
    test-nodes-are-endpoints-plus-nodedata = {
      expr = acyclic.nodes;
      expected = [
        addrA
        addrB
        addrC
      ];
    };
    # Items are NOT node seeds: only edges and nodeData are.
    test-items-do-not-seed-nodes = {
      expr = itemOnly.nodes;
      expected = [ ];
    };
    test-nodedata-seeds-an-isolated-node = {
      expr = seeded.nodes;
      expected = [ addrA ];
    };
    test-nodedata-reads-back = {
      expr = acyclic.nodeData addrA;
      expected = {
        field = "font";
      };
    };
    test-nodedata-absent-is-empty = {
      expr = acyclic.nodeData addrB;
      expected = { };
    };

    # ── the accessor ──
    test-adjacency = {
      expr = acyclic.edges addrA;
      expected = [ addrB ];
    };
    test-adjacency-leaf = {
      expr = acyclic.edges addrC;
      expected = [ ];
    };
    test-parallel-references-derive-both-hops = {
      expr = lib.length parallel.derivedEdges;
      expected = 2;
    };
    test-parallel-references-are-one-successor = {
      expr = parallel.edges addrA;
      expected = [ addrB ];
    };

    # ── the containment dimension survives the derivation ──
    test-parents-reach-the-accessor = {
      expr = parented.parent addrA;
      expected = addrC;
    };
    # ...and stay disjoint from the derived edges, exactly as for mkGraph: a parent is not a hop.
    test-parents-are-not-derived-edges = {
      expr = parented.edges addrA;
      expected = [ addrB ];
    };
    test-parents-seed-nodes = {
      expr = parented.nodes;
      expected = [
        addrA
        addrB
        addrC
      ];
    };
    # The zero arm of the same lookup: no `parents`, same shape of call, in the same run.
    test-control-no-parents-is-null = {
      expr = acyclic.parent addrA;
      expected = null;
    };
    # A parent naming a node that appears in NEITHER `nodeData` nor any derived edge still seeds
    # it — `parents` is a node source, exactly as it is for mkGraph. (`parented` has empty
    # nodeData and derives only addrA -> addrB, so addrC arrives through the parent alone.)
    test-parents-seed-a-node-nothing-else-mentions = {
      expr = builtins.elem addrC parented.nodes;
      expected = true;
    };
    # A parent CONTRADICTING a derived edge changes neither index: the derived hop still answers
    # `edges`, the declared parent still answers `parent`.
    test-parents-contradicting-a-derived-edge-stay-disjoint = {
      expr = {
        derived = parentAgainstEdge.edges addrA;
        declared = parentAgainstEdge.parent addrB;
        parentIsNotAnEdge = parentAgainstEdge.edges addrB;
      };
      expected = {
        derived = [ addrB ];
        declared = addrA;
        parentIsNotAnEdge = [ ];
      };
    };
    # ...so a parent cannot close a cycle in the derived graph.
    test-parents-cannot-create-a-cycle = {
      expr = cyclePaths { inherit (parentAgainstEdge) nodes edges; };
      expected = [ ];
    };
    # POSITIVE CONTROL for that zero, same instrument same run: derive the back-hop instead of
    # declaring it and the cycle is found.
    test-control-derived-back-edge-is-a-cycle = {
      expr = builtins.length (cyclePaths {
        inherit (derivedBackEdge) nodes edges;
      });
      expected = 1;
    };

    # ── a throwing scan or projection is the CALLER's throw, carried not swallowed ──
    # Construction forces neither: the result is an accessor before anything is scanned.
    test-throwing-scan-not-forced-by-construction = {
      expr =
        (fromScan {
          items = [ (item addrA [ (refTo addrB "hop-1") ]) ];
          scan = _: throw "scan boom";
          inherit project;
        }) ? nodes;
      expected = true;
    };
    test-throwing-scan-propagates-on-force = {
      expr =
        throws
          (fromScan {
            items = [ (item addrA [ (refTo addrB "hop-1") ]) ];
            scan = _: throw "scan boom";
            inherit project;
          }).nodes;
      expected = true;
    };
    test-throwing-projection-propagates-on-force = {
      expr =
        throws
          (fromScan {
            items = [ (item addrA [ (refTo addrB "hop-1") ]) ];
            inherit scan;
            project = _: throw "project boom";
          }).nodes;
      expected = true;
    };
    # The zero arm of that predicate: a well-formed graph forces clean through the same `throws`.
    test-control-well-formed-does-not-throw = {
      expr = throws acyclic.nodes;
      expected = false;
    };

    # ── compound keys stay opaque, through the cycle machinery ──
    # The separator is inert: the walk is over the whole address, never over an identity or a
    # field alone. A derivation that split on ":" would report a three-node cycle over "a1b2c3d4",
    # "e5f6a7b8", "f1f2f3f4" — or no cycle at all.
    test-cycle-over-compound-keys = {
      expr = lib.length (cyclePaths {
        inherit (cyclic) nodes edges;
      });
      expected = 1;
    };
    test-cycle-walk-is-ordered-over-compound-keys = {
      expr = lib.head (cyclePaths {
        inherit (cyclic) nodes edges;
      });
      expected = [
        addrA
        addrB
        addrC
      ];
    };

    # ── CONTROLS ──
    # The acyclic arm of the same instrument, in the same run: without it the cycle assertions
    # above cannot distinguish "no cycle here" from "cyclePaths never ran".
    test-control-acyclic-reports-no-cycle = {
      expr = cyclePaths { inherit (acyclic) nodes edges; };
      expected = [ ];
    };
    # The empty arm: nothing to scan derives nothing, rather than throwing or inventing a node.
    test-control-empty-scan-derives-no-edges = {
      expr = empty.derivedEdges;
      expected = [ ];
    };
    test-control-empty-scan-has-no-nodes = {
      expr = empty.nodes;
      expected = [ ];
    };
    test-control-empty-scan-reports-no-cycle = {
      expr = cyclePaths { inherit (empty) nodes edges; };
      expected = [ ];
    };
  };
}
