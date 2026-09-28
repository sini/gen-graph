# ── BOUNDARY MARKS AND THEIR DIAGNOSTIC ─────────────────────────────────────────
# A mark filters a node's edges before any query sees them. The property worth
# guarding is not that it filters — that is one `builtins.filter` — but that it CANNOT
# BE SILENT: every arm below that asserts a narrowed answer is paired with the
# diagnostic that names the mark responsible, and every arm that asserts a diagnostic
# is paired with an unmarked control on the same graph in the same run, which must
# produce the full answer and an EMPTY diagnostic. Without that control an
# always-diagnosing accessor would pass every test here.
{ genGraph, ... }:
let
  inherit (genGraph)
    labeledFrom
    labeledFixtures
    boundedBy
    query
    regex
    ;
  r = regex;
  sorted = builtins.sort builtins.lessThan;

  gate =
    labeledFrom
      {
        e = id: if id == "gate" then [ "ok" ] else [ ];
        q = id: if id == "gate" then [ "no" ] else [ ];
      }
      [
        "gate"
        "no"
        "ok"
      ];
  sealed = {
    name = "sealed";
    admits = l: l == "e";
  };
  quiet = {
    name = "quiet";
    admits = l: l != "q";
  };
  marked = boundedBy (id: if id == "gate" then [ sealed ] else [ ]) gate;
  unmarked = boundedBy (_: [ ]) gate;
  doublyMarked = boundedBy (
    id:
    if id == "gate" then
      [
        sealed
        quiet
      ]
    else
      [ ]
  ) gate;
  bothLabels = r.alt [
    (r.lit "e")
    (r.lit "q")
  ];
in
{
  flake.tests.boundaries = {
    test-bounded-admits-only-what-the-mark-permits = {
      expr = marked.labeledEdges "gate";
      expected = [
        {
          label = "e";
          target = "ok";
        }
      ];
    };
    test-bounded-CONTROL-unmarked-node-keeps-every-edge = {
      expr = unmarked.labeledEdges "gate";
      expected = [
        {
          label = "e";
          target = "ok";
        }
        {
          label = "q";
          target = "no";
        }
      ];
    };
    test-bounded-withheld-edge-names-its-mark = {
      expr = marked.withheld "gate";
      expected = [
        {
          label = "q";
          target = "no";
          marks = [ "sealed" ];
        }
      ];
    };
    test-bounded-CONTROL-unmarked-node-has-an-empty-diagnostic = {
      # the arm that stops "names a mark" being satisfied by naming one always
      expr = unmarked.withheld "gate";
      expected = [ ];
    };
    test-bounded-several-marks-are-all-named = {
      # picking one would make the report depend on mark order
      expr = map (e: e.marks) (doublyMarked.withheld "gate");
      expected = [
        [
          "sealed"
          "quiet"
        ]
      ];
    };
    test-bounded-a-mark-that-withholds-nothing-reports-nothing = {
      expr =
        let
          permissive = boundedBy (_: [
            {
              name = "open";
              admits = _: true;
            }
          ]) gate;
        in
        {
          edges = permissive.labeledEdges "gate";
          withheld = permissive.withheld "gate";
        };
      expected = {
        edges = [
          {
            label = "e";
            target = "ok";
          }
          {
            label = "q";
            target = "no";
          }
        ];
        withheld = [ ];
      };
    };

    # ── the mark reaches the query, and only ever narrows it ──
    test-bounded-query-through-a-mark-narrows = {
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = marked;
            from = "gate";
            follow = bothLabels;
          }
      );
      expected = [ "ok" ];
    };
    test-bounded-CONTROL-the-same-query-unmarked-answers-in-full = {
      expr = sorted (
        query
          {
            mode = "all";
          }
          {
            graph = unmarked;
            from = "gate";
            follow = bothLabels;
          }
      );
      expected = [
        "no"
        "ok"
      ];
    };
    test-bounded-narrowing-is-structural-across-the-whole-graph = {
      # every bounded edge set is a subset of the unbounded one, at every node:
      # the construction removes and never adds, so widening is unsayable
      expr = builtins.all (
        n:
        builtins.all (e: builtins.elem e (labeledFixtures.world.labeledEdges n)) (
          (boundedBy (_: [
            {
              name = "contains-only";
              admits = l: l == "contains";
            }
          ]) labeledFixtures.world).labeledEdges
            n
        )
      ) labeledFixtures.world.nodes;
      expected = true;
    };
    test-bounded-admitted-and-withheld-partition-the-edges = {
      expr = builtins.all (
        n:
        let
          b = boundedBy (_: [
            {
              name = "contains-only";
              admits = l: l == "contains";
            }
          ]) labeledFixtures.world;
        in
        builtins.length (b.labeledEdges n) + builtins.length (b.withheld n)
        == builtins.length (labeledFixtures.world.labeledEdges n)
      ) labeledFixtures.world.nodes;
      expected = true;
    };
    test-bounded-preserves-the-node-set = {
      expr = (boundedBy (_: [ ]) labeledFixtures.world).nodes;
      expected = labeledFixtures.world.nodes;
    };
    test-bounded-laziness-poison-unreached = {
      # the per-node memo builds a spine, never a forced classification: a node the
      # walk does not reach keeps its throwing accessor unforced
      expr =
        query
          {
            mode = "all";
          }
          {
            graph = boundedBy (_: [ ]) labeledFixtures.poisoned;
            from = "a";
            follow = r.parse "safe";
          };
      expected = [ "b" ];
    };
    test-bounded-composes-under-transposition = {
      # a mark applied before transposing still withholds the same edge, read from
      # the other end — the two constructions are independent
      expr = (genGraph.labeledTranspose marked).labeledEdges "no";
      expected = [ ];
    };
    test-bounded-CONTROL-the-unmarked-transpose-keeps-that-edge = {
      expr = (genGraph.labeledTranspose unmarked).labeledEdges "no";
      expected = [
        {
          label = "q";
          target = "gate";
        }
      ];
    };
  };
}
