{ lib, genGraph, ... }:
let
  inherit (genGraph)
    reachableFrom
    reachableWhere
    canReach
    selfReachable
    ancestorsOf
    pathsBetween
    ;
  inherit (genGraph) fixtures mkGraph;

  # A chain accessor of n nodes, (n-1) → (n-2) → … → 0. `pathsBetween`'s ceiling is DEPTH,
  # not n (`star` at 16,000 nodes and depth 1 returns), so a chain is the shape that reaches
  # it at the smallest node count. Same construction as `ci/tests/preorder.nix`'s.
  chain =
    n:
    let
      pad =
        i:
        let
          s = toString i;
        in
        builtins.substring 0 (6 - builtins.stringLength s) "000000" + s;
      key = i: "n" + pad i;
      m = builtins.listToAttrs (
        map (i: {
          name = key i;
          value = if i == 0 then [ ] else [ (key (i - 1)) ];
        }) (builtins.genList (i: i) n)
      );
    in
    {
      top = key (n - 1);
      bottom = key 0;
      edges = k: m.${k} or [ ];
    };

  # A `parent` accessor of n nodes, same numbering as `chain` above but reversed into a
  # single-parent function rather than a children list — the shape `ancestorsOf` walks.
  # `ancestorsChain n`'s `top` has `n - 1` ancestors (`key (n - 2)` down to `key 0`), one
  # fewer than the node count, since `ancestorsOf` excludes the start.
  ancestorsChain =
    n:
    let
      pad =
        i:
        let
          s = toString i;
        in
        builtins.substring 0 (6 - builtins.stringLength s) "000000" + s;
      key = i: "n" + pad i;
      m = builtins.listToAttrs (
        map (i: {
          name = key i;
          value = if i == 0 then null else key (i - 1);
        }) (builtins.genList (i: i) n)
      );
    in
    {
      top = key (n - 1);
      parent = k: m.${k} or null;
    };

  returns = v: (builtins.tryEval (builtins.deepSeq v v)).success;
in
{
  flake.tests.traverse = {
    test-reachable-chain = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.chain "a");
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    test-reachable-diamond = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.diamond "a");
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    test-reachable-from-leaf = {
      expr = reachableFrom fixtures.chain "d";
      expected = [ ];
    };
    test-reachable-cyclic = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.cyclic "a");
      expected = [
        "b"
        "c"
      ];
    };
    test-reachable-nonexistent = {
      expr = reachableFrom fixtures.chain "zzz";
      expected = [ ];
    };
    test-reachable-where-filter = {
      expr = builtins.sort builtins.lessThan (
        reachableWhere fixtures.serviceGraph "web" (id: id != "cache")
      );
      expected = [
        "api"
        "db"
      ];
    };
    test-reachable-where-all = {
      expr = builtins.sort builtins.lessThan (reachableWhere fixtures.serviceGraph "web" (_: true));
      expected = [
        "api"
        "cache"
        "db"
      ];
    };
    test-ancestors-tree = {
      expr = ancestorsOf fixtures.tree "grandchild";
      expected = [
        "child1"
        "root"
      ];
    };
    test-ancestors-root = {
      expr = ancestorsOf fixtures.tree "root";
      expected = [ ];
    };
    test-ancestors-child = {
      expr = ancestorsOf fixtures.tree "child2";
      expected = [ "root" ];
    };
    test-paths-diamond = {
      expr = builtins.length (pathsBetween fixtures.diamond "a" "d");
      expected = 2;
    };
    test-paths-no-path = {
      expr = pathsBetween fixtures.chain "d" "a";
      expected = [ ];
    };
    test-paths-cyclic-terminates = {
      expr = builtins.length (pathsBetween fixtures.cyclic "a" "c");
      expected = 1;
    };
    test-paths-self = {
      expr = pathsBetween fixtures.chain "a" "a";
      expected = [ [ "a" ] ];
    };
    test-ancestors-cyclic-terminates = {
      expr =
        let
          # Create a graph with cyclic parent: a->b->a
          g = mkGraph {
            parents = [
              {
                from = "a";
                to = "b";
              }
              {
                from = "b";
                to = "a";
              }
            ];
          };
        in
        ancestorsOf g "a";
      expected = [ "b" ];
    };
    test-reachable-disconnected = {
      expr = reachableFrom fixtures.disconnected "island";
      expected = [ ];
    };
    test-reachable-disconnected-from-connected = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.disconnected "a");
      expected = [ "b" ];
    };

    # --- canReach ---

    test-canReach-true = {
      expr = canReach fixtures.serviceGraph "web" "db";
      expected = true;
    };
    test-canReach-false = {
      expr = canReach fixtures.serviceGraph "db" "web";
      expected = false;
    };
    test-canReach-direct = {
      expr = canReach fixtures.chain "a" "b";
      expected = true;
    };
    test-canReach-transitive = {
      expr = canReach fixtures.chain "a" "d";
      expected = true;
    };
    test-canReach-self-cyclic = {
      expr = canReach fixtures.cyclic "a" "a";
      expected = true; # a→b→c→a: a can reach itself through the cycle
    };
    test-canReach-nonexistent = {
      expr = canReach fixtures.chain "a" "zzz";
      expected = false;
    };

    # The operator stops EXPANDING at the target but never suppresses its ENTRY, so these
    # pin the entry at the boundaries where the two are easiest to confuse.

    # from == to with no cycle: the source is not its own successor, and suppressing
    # expansion at a node never visited cannot manufacture a membership.
    test-canReach-self-acyclic = {
      expr = canReach fixtures.chain "a" "a";
      expected = false;
    };
    # from == to over a self-loop: the target IS in the start set, so it is admitted before
    # the operator is consulted on it at all.
    test-canReach-self-loop = {
      expr = canReach (mkGraph {
        edges = [
          {
            from = "x";
            to = "x";
          }
        ];
      }) "x" "x";
      expected = true;
    };
    # Two paths converge on the target. Whichever branch reaches it first prunes it; the
    # other branch is unaffected, because only the target's own expansion is suppressed.
    test-canReach-diamond-merge = {
      expr = canReach fixtures.diamond "a" "d";
      expected = true;
    };
    # ── THE DOMAIN BOUNDARY, GUARDED IN-SUITE ──
    # Suppressing the target's expansion means its out-edges are never read once it is
    # reached, so canReach ANSWERS on an accessor that refuses them where a full walk
    # propagates the refusal. That is a property of the operator, not a happy accident, and
    # without a cell here a refactor that forced `edges item.key` before consulting the guard
    # would falsify it with every other cell still green.
    #
    # These are assertable in `flake.tests` — and belong here rather than in `tests-error.nix`
    # — precisely because neither `expr` throws: `tryEval` returns a record either way, so the
    # batch asserter behind `checks.default` can force them.
    test-canReach-answers-past-a-refusing-target = {
      # a→b→c with the accessor refusing anything past b. `c` IS reachable, so `true` is the
      # correct answer, and stopping at the target is what makes it available.
      expr = builtins.tryEval (
        canReach {
          edges =
            id:
            if id == "a" then
              [ "b" ]
            else if id == "b" then
              [ "c" ]
            else
              throw "accessor refuses ${id}";
        } "a" "c"
      );
      expected = {
        success = true;
        value = true;
      };
    };
    # The two-sided half, and it is what keeps the claim from reading as "canReach got more
    # forgiving". Move the refusal ONTO the path, before the target: the walk cannot reach the
    # target without reading it, so the refusal propagates exactly as it always did.
    test-canReach-still-refuses-a-refusal-on-the-path = {
      expr = builtins.tryEval (
        canReach {
          edges = id: if id == "a" then [ "b" ] else throw "accessor refuses ${id}";
        } "a" "c"
      );
      expected = {
        success = false;
        value = false;
      };
    };

    # The target sits inside a cycle reached from outside it. Pruning the target removes the
    # cycle's continuation, which is exactly the sub-closure nothing reads.
    test-canReach-target-in-cycle = {
      expr =
        let
          g = mkGraph {
            edges = [
              {
                from = "x";
                to = "a";
              }
              {
                from = "a";
                to = "b";
              }
              {
                from = "b";
                to = "a";
              }
            ];
          };
        in
        [
          (canReach g "x" "a")
          (canReach g "x" "b")
        ];
      expected = [
        true
        true
      ];
    };

    # --- selfReachable ---

    test-selfReachable-cyclic = {
      expr = selfReachable fixtures.cyclic "a";
      expected = true;
    };
    test-selfReachable-acyclic = {
      expr = selfReachable fixtures.chain "a";
      expected = false;
    };
    test-selfReachable-leaf = {
      expr = selfReachable fixtures.chain "d";
      expected = false;
    };
    test-selfReachable-self-loop = {
      expr = selfReachable (mkGraph {
        edges = [
          {
            from = "x";
            to = "x";
          }
        ];
      }) "x";
      expected = true;
    };

    # ── pathsBetween's DEPTH CAP AND ITS REFUSAL (ADR-0009 fourth amendment / ADR-0032) ──
    #
    # The claim is CATCHABILITY: what these replace is a `stack overflow; max-call-depth
    # exceeded` ABORT, which `tryEval` cannot see, so `success == false` is a reading the old
    # construction could not produce at any depth. The message's own text — that it names
    # `pathsBetween` — is asserted in `ci/tests-error.nix`, the only output that can.
    #
    # ★ THE BOUNDARY IS `maxDepth + 1` NODES, NOT `maxDepth`, and the extra node is the
    # terminating check rather than an off-by-one: `current == endId` is consulted BEFORE the
    # guard, so the target frame never descends and never has to fit under the cap. A chain
    # of `maxDepth + 1` therefore still yields its one path.
    test-pathsbetween-refuses-past-maxdepth-catchably =
      let
        c = chain 10;
      in
      {
        expr = returns (
          pathsBetween {
            inherit (c) edges;
            maxDepth = 8;
          } c.top c.bottom
        );
        expected = false;
      };

    # LIVE CONTROL, same run: one node shorter and the walk returns its path whole. Without
    # it the cell above is consistent with a guard that refuses every call.
    test-control-pathsbetween-returns-at-the-cap-boundary =
      let
        c = chain 9;
      in
      {
        expr = builtins.length (
          builtins.head (
            pathsBetween {
              inherit (c) edges;
              maxDepth = 8;
            } c.top c.bottom
          )
        );
        expected = 9;
      };

    # ★ THE CELL AT THE SHIPPED DEFAULT — the only one that says the default arrives before
    # the evaluator's own ceiling rather than after it. Measured on this shape at `374b0ad`:
    # returns at depth 2,497, aborts at 2,498. Raise the default past that and this reads ☢️
    # rather than ❌, the abort killing the cell instead of failing it.
    test-pathsbetween-default-cap-refuses-below-the-evaluator-ceiling =
      let
        c = chain 2002;
      in
      {
        expr = returns (pathsBetween { inherit (c) edges; } c.top c.bottom);
        expected = false;
      };

    test-control-pathsbetween-default-cap-returns-just-below-it =
      let
        c = chain 2001;
      in
      {
        expr = builtins.length (builtins.head (pathsBetween { inherit (c) edges; } c.top c.bottom));
        expected = 2001;
      };

    # ── ancestorsOf's DEPTH CAP AND ITS REFUSAL (ADR-0009 fourth amendment / ADR-0032) ──
    #
    # Same claim as `pathsBetween` above: CATCHABILITY. `success == false` is a reading the
    # old, unguarded `go` could not produce at any depth. The message's own text is asserted
    # in `ci/tests-error.nix`.
    #
    # ★ THE BOUNDARY IS EXACTLY `maxDepth` ANCESTORS, unlike `pathsBetween`'s `maxDepth + 1`:
    # `ancestorsOf`'s guard checks the depth of the node CURRENTLY being walked, and there is
    # no terminating check exempting one extra frame the way `current == endId` does there.
    test-ancestorsof-refuses-past-maxdepth-catchably =
      let
        c = ancestorsChain 10;
      in
      {
        expr = returns (
          ancestorsOf {
            inherit (c) parent;
            maxDepth = 8;
          } c.top
        );
        expected = false;
      };

    # LIVE CONTROL, same run: one ancestor fewer and the walk returns it whole. Without it
    # the cell above is consistent with a guard that refuses every call.
    test-control-ancestorsof-returns-at-the-cap-boundary =
      let
        c = ancestorsChain 9;
      in
      {
        expr = builtins.length (
          ancestorsOf {
            inherit (c) parent;
            maxDepth = 8;
          } c.top
        );
        expected = 8;
      };

    # ★ THE CELL AT THE SHIPPED DEFAULT — the only one that says the default arrives before
    # the evaluator's own ceiling rather than after it. Measured on this shape at `eb638eb`:
    # returns at 9,988 ancestors, aborts at 9,989. Raise the default past that and this reads
    # ☢️ rather than ❌, the abort killing the cell instead of failing it.
    test-ancestorsof-default-cap-refuses-below-the-evaluator-ceiling =
      let
        c = ancestorsChain 8002;
      in
      {
        expr = returns (ancestorsOf { inherit (c) parent; } c.top);
        expected = false;
      };

    test-control-ancestorsof-default-cap-returns-just-below-it =
      let
        c = ancestorsChain 8001;
      in
      {
        expr = builtins.length (ancestorsOf { inherit (c) parent; } c.top);
        expected = 8000;
      };
  };
}
