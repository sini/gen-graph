# preorder.nix — foldPreorder / expandPreorder / foldReach.
#
# Covers: DFS first-occurrence pre-order (node-before-children, siblings in list
# order); cycle-break; per-edge classFilter projection + negative-edge suppression
# (foldReach); lazy/demand-generated edges + seedable seen0 (expandPreorder);
# dual-bucket classify + null-key unguarded (foldPreorder); empty/degenerate seeds.
{ genGraph, ... }:
let
  inherit (genGraph) foldPreorder expandPreorder foldReach;
  sorted = builtins.sort builtins.lessThan;
in
{
  flake.tests.preorder = {

    # ── expandPreorder (den-hoag forwardExpand shape) ──────────────────────────

    # DFS pre-order + first-occurrence dedup over a diamond a→{b,c}, b→d, c→d:
    # a first, b before c (sibling order), d discovered under b then skipped under c.
    test-expand-preorder-first-occurrence =
      let
        db = {
          a.includes = [
            "b"
            "c"
          ];
          b.includes = [ "d" ];
          c.includes = [ "d" ];
          d.includes = [ ];
        };
        node = k: { key = k; } // db.${k};
      in
      {
        expr =
          (expandPreorder {
            roots = [ (node "a") ];
            key = f: f.key;
            edges = p: map node p.includes;
            emit = f: _p: f.key;
          }).nodes;
        expected = [
          "a"
          "b"
          "d"
          "c"
        ];
      };

    # cycle a→b→a terminates; each node emitted once, in discovery order.
    test-expand-cycle-terminates =
      let
        db = {
          a.includes = [ "b" ];
          b.includes = [ "a" ];
        };
        node = k: { key = k; } // db.${k};
      in
      {
        expr =
          (expandPreorder {
            roots = [ (node "a") ];
            key = f: f.key;
            edges = p: map node p.includes;
            emit = f: _p: f.key;
          }).nodes;
        expected = [
          "a"
          "b"
        ];
      };

    # seen0 pre-seed prunes b's whole subtree (b never emitted, so d is reached only
    # via c) — constraint-driven drop-pruning.
    test-expand-seen0-prunes-subtree =
      let
        db = {
          a.includes = [
            "b"
            "c"
          ];
          b.includes = [ "d" ];
          c.includes = [ "e" ];
          d.includes = [ ];
          e.includes = [ ];
        };
        node = k: { key = k; } // db.${k};
      in
      {
        expr =
          (expandPreorder {
            roots = [ (node "a") ];
            key = f: f.key;
            edges = p: map node p.includes;
            emit = f: _p: f.key;
            seen0 = {
              b = true;
            };
          }).nodes;
        expected = [
          "a"
          "c"
          "e"
        ];
      };

    # Laziness: a seen0-pruned frame is NEVER forced. `boom.includes` throws; boom is a
    # child of `a` but pre-seeded in seen0, so it is skipped before `edges`/`resolve`
    # touch it. A strict traversal would force the throw. (Kahn 1974 demand property.)
    test-expand-lazy-pruned-not-forced =
      let
        db = {
          a.includes = [
            "safe"
            "boom"
          ];
          safe.includes = [ ];
          boom.includes = throw "forced a pruned frame";
        };
        node = k: { key = k; } // db.${k};
      in
      {
        expr =
          (expandPreorder {
            roots = [ (node "a") ];
            key = f: f.key;
            edges = p: map node p.includes;
            emit = f: _p: f.key;
            seen0 = {
              boom = true;
            };
          }).nodes;
        expected = [
          "a"
          "safe"
        ];
      };

    # Demand-generated edges: a parametric frame's `includes` exist only AFTER `resolve`
    # invokes it with context — `edges` reads the resolved payload, not the raw frame.
    test-expand-resolve-then-edges =
      let
        ctx = {
          host = "igloo";
        };
        # root is a wrapped fn; resolve invokes it with ctx, producing content + includes.
        root = {
          key = "root";
          __wrap = true;
          fn = c: {
            content = "root@${c.host}";
            includes = [ leaf ];
          };
        };
        leaf = {
          key = "leaf";
          content = "leaf";
          includes = [ ];
        };
        res = expandPreorder {
          roots = [ root ];
          key = f: f.key;
          resolve = f: if f.__wrap or false then f.fn ctx else f;
          edges = p: p.includes;
          emit = _f: p: p.content;
        };
      in
      {
        expr = res.nodes;
        expected = [
          "root@igloo"
          "leaf"
        ];
      };

    # nodes0 seed prepended; seen threads through so a seeded key is not re-emitted.
    test-expand-nodes0-and-seen-return =
      let
        db = {
          a.includes = [ "b" ];
          b.includes = [ ];
        };
        node = k: { key = k; } // db.${k};
        res = expandPreorder {
          roots = [ (node "a") ];
          key = f: f.key;
          edges = p: map node p.includes;
          emit = f: _p: f.key;
          nodes0 = [ "SEED" ];
        };
      in
      {
        expr = {
          nodes = res.nodes;
          seenKeys = sorted (builtins.attrNames res.seen);
        };
        expected = {
          nodes = [
            "SEED"
            "a"
            "b"
          ];
          seenKeys = [
            "a"
            "b"
          ];
        };
      };

    test-expand-empty-roots = {
      expr =
        (expandPreorder {
          roots = [ ];
          key = f: f.key;
          edges = _p: [ ];
        }).nodes;
      expected = [ ];
    };

    # ── foldReach (den-hoag reach shape) ───────────────────────────────────────

    # Per-edge classFilter projection: the root→api edge is filtered to the "nixos"
    # class, so api's home-manager-only node is excluded (F9 no over-reach); the
    # root→db edge has a null filter (all classes). Transitive over the target's edges.
    test-reach-per-edge-classfilter =
      let
        content = {
          db = [
            {
              key = "opt-a";
              nixos = true;
            }
            {
              key = "opt-b";
              home-manager = true;
            }
          ];
          api = [
            {
              key = "opt-c";
              nixos = true;
            }
            {
              key = "opt-hm";
              home-manager = true;
            }
          ];
        };
        edgeMap = {
          root = [
            {
              target = "db";
              classFilter = null;
            }
            {
              target = "api";
              classFilter = "nixos";
            }
          ];
        };
        edgesAt = id: edgeMap.${id} or [ ];
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project =
            e: builtins.filter (n: e.classFilter == null || n ? ${e.classFilter}) (content.${e.target} or [ ]);
          itemKey = n: n.key;
          visited0 = {
            root = true;
          };
        };
      in
      {
        expr = map (n: n.key) res.nodes;
        expected = [
          "opt-a" # db, null filter
          "opt-b" # db, null filter
          "opt-c" # api, nixos filter passes
          # opt-hm excluded: home-manager node under a nixos-scoped edge
        ];
      };

    # Negative-edge suppression: the `edges` accessor bakes suppression in (returns a
    # vertex's edges MINUS the suppressed targets), so the fold is suppression-aware
    # by construction — the root→api edge is dropped, and opt-c never enters reach.
    test-reach-negative-edge-suppression =
      let
        content = {
          db = [ { key = "opt-a"; } ];
          api = [ { key = "opt-c"; } ];
        };
        edgeMap = {
          root = [
            { target = "db"; }
            { target = "api"; }
          ];
        };
        suppressed = {
          api = true;
        };
        edgesAt = id: builtins.filter (e: !(suppressed ? ${e.target})) (edgeMap.${id} or [ ]);
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project = e: content.${e.target} or [ ];
          itemKey = n: n.key;
          visited0 = {
            root = true;
          };
        };
      in
      {
        expr = map (n: n.key) res.nodes;
        expected = [ "opt-a" ];
      };

    # Transitive follow: root→db, then db→api (an edge on the target vertex).
    test-reach-transitive =
      let
        content = {
          db = [ { key = "opt-a"; } ];
          api = [ { key = "opt-c"; } ];
        };
        edgeMap = {
          root = [ { target = "db"; } ];
          db = [ { target = "api"; } ];
        };
        edgesAt = id: edgeMap.${id} or [ ];
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project = e: content.${e.target} or [ ];
          itemKey = n: n.key;
          visited0 = {
            root = true;
          };
        };
      in
      {
        expr = map (n: n.key) res.nodes;
        expected = [
          "opt-a"
          "opt-c"
        ];
      };

    # Cycle over edges (root→db→root) terminates via the target visited set.
    test-reach-edge-cycle-terminates =
      let
        content = {
          db = [ { key = "opt-a"; } ];
        };
        edgeMap = {
          root = [ { target = "db"; } ];
          db = [ { target = "root"; } ];
        };
        edgesAt = id: edgeMap.${id} or [ ];
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project = e: content.${e.target} or [ ];
          itemKey = n: n.key;
          visited0 = {
            root = true;
          };
        };
      in
      {
        expr = map (n: n.key) res.nodes;
        expected = [ "opt-a" ];
      };

    # First-occurrence item dedup ACROSS vertices: db and api both project the same
    # item key `opt-x`; the witness keeps the first occurrence only.
    test-reach-item-dedup-across-vertices =
      let
        content = {
          db = [ { key = "opt-x"; } ];
          api = [ { key = "opt-x"; } ];
        };
        edgeMap = {
          root = [
            { target = "db"; }
            { target = "api"; }
          ];
        };
        edgesAt = id: edgeMap.${id} or [ ];
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project = e: content.${e.target} or [ ];
          itemKey = n: n.key;
          visited0 = {
            root = true;
          };
        };
      in
      {
        expr = map (n: n.key) res.nodes;
        expected = [ "opt-x" ];
      };

    # seededOwn: seen0 + nodes0 seed the witness (the structural component of reach);
    # an edge that re-projects a seeded key is deduped against it (own-first wins).
    test-reach-seeded-structural =
      let
        content = {
          db = [
            { key = "structural-1"; } # already in the seed → deduped
            { key = "edge-1"; }
          ];
        };
        edgeMap = {
          root = [ { target = "db"; } ];
        };
        edgesAt = id: edgeMap.${id} or [ ];
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project = e: content.${e.target} or [ ];
          itemKey = n: n.key;
          visited0 = {
            root = true;
          };
          seen0 = {
            structural-1 = true;
          };
          nodes0 = [ { key = "structural-1"; } ];
        };
      in
      {
        expr = map (n: n.key) res.nodes;
        expected = [
          "structural-1" # from the seed
          "edge-1" # structural-1 re-projection deduped away
        ];
      };

    # itemKey → null keeps every item (no dedup) — the NULL-KEEP direction.
    test-reach-null-itemkey-keeps-all =
      let
        content = {
          db = [
            { key = "dup"; }
            { key = "dup"; }
          ];
        };
        edgeMap = {
          root = [ { target = "db"; } ];
        };
        edgesAt = id: edgeMap.${id} or [ ];
        res = foldReach {
          roots = edgesAt "root";
          edges = edgesAt;
          target = e: e.target;
          project = e: content.${e.target} or [ ];
          itemKey = _n: null;
          visited0 = {
            root = true;
          };
        };
      in
      {
        expr = builtins.length res.nodes;
        expected = 2;
      };

    # ── foldPreorder (the primitive: compat aspectIncludeWalk shape) ────────────

    # Dual-bucket classify over a nested structure: each `includes` entry is a policy
    # (→ recs), a bare fn (→ bares), or a sub-record (→ recurse). Cycle-key = `.key`.
    test-foldpreorder-dual-bucket-classify =
      let
        root = {
          key = "root";
          includes = [
            {
              kind = "policy";
              name = "p1";
            }
            {
              key = "sub";
              includes = [
                {
                  kind = "policy";
                  name = "p2";
                }
                {
                  kind = "bare";
                }
              ];
            }
          ];
        };
        res = foldPreorder {
          roots = [ root ];
          key = v: v.key or null;
          acc = {
            recs = [ ];
            bares = [ ];
          };
          expand =
            acc: v:
            let
              incs = v.includes or [ ];
            in
            {
              acc = {
                recs = acc.recs ++ builtins.filter (x: (x.kind or null) == "policy") incs;
                bares = acc.bares ++ builtins.filter (x: (x.kind or null) == "bare") incs;
              };
              children = builtins.filter (x: x ? includes) incs;
            };
        };
      in
      {
        expr = {
          recs = map (r: r.name) res.acc.recs;
          bares = builtins.length res.acc.bares;
        };
        expected = {
          recs = [
            "p1"
            "p2"
          ];
          bares = 1;
        };
      };

    # A null key is never guarded — two structurally distinct keyless frames both
    # expand (no false dedup), and they terminate by finite authored structure.
    test-foldpreorder-null-key-unguarded =
      let
        res = foldPreorder {
          roots = [
            { tag = "x"; }
            { tag = "y"; }
          ];
          key = _v: null;
          acc = [ ];
          expand = acc: v: {
            acc = acc ++ [ v.tag ];
            children = [ ];
          };
        };
      in
      {
        expr = res.acc;
        expected = [
          "x"
          "y"
        ];
      };

    # Degenerate: empty roots return the seed accumulator and visited set untouched.
    test-foldpreorder-empty-roots =
      let
        res = foldPreorder {
          roots = [ ];
          key = _v: null;
          expand = acc: _v: {
            inherit acc;
            children = [ ];
          };
          acc = "seed";
          visited = {
            pre = true;
          };
        };
      in
      {
        expr = {
          acc = res.acc;
          visited = builtins.attrNames res.visited;
        };
        expected = {
          acc = "seed";
          visited = [ "pre" ];
        };
      };

    # The visited set is returned and reflects every first-occurrence key.
    test-foldpreorder-returns-visited =
      let
        db = {
          a.includes = [ "b" ];
          b.includes = [ ];
        };
        node = k: { key = k; } // db.${k};
        res = foldPreorder {
          roots = [ (node "a") ];
          key = v: v.key;
          acc = null;
          expand = acc: v: {
            inherit acc;
            children = map node v.includes;
          };
        };
      in
      {
        expr = sorted (builtins.attrNames res.visited);
        expected = [
          "a"
          "b"
        ];
      };
  };
}
