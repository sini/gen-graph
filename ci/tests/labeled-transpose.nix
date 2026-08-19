# ── THE LABELED TRANSPOSE ───────────────────────────────────────────────────────
# The claim is not that a reverse index exists — `global.nix` has had one — but that
# the reverse read CARRIES THE LABEL, so a reverse query is the forward construction
# over a transposed accessor with the query's own parameters untouched. The control
# that makes the claim mean anything is the composition it replaces: forgetting the
# labels and transposing the plain accessor, which answers with bare targets and has
# nothing left for a label regex to read.
{ genGraph, ... }:
let
  inherit (genGraph)
    labeledFrom
    labeledFixtures
    labeledTranspose
    forgetLabels
    transpose
    query
    regex
    ;
  r = regex;
  sorted = builtins.sort builtins.lessThan;
  byJson = builtins.sort (a: b: builtins.toJSON a < builtins.toJSON b);

  diamond = labeledFrom {
    nodes = [
      "l"
      "r"
      "s"
      "t"
    ];
    perLabel.e =
      id:
      {
        s = [
          "l"
          "r"
        ];
        l = [ "t" ];
        r = [ "t" ];
      }
      .${id} or [ ];
  };
in
{
  flake.tests.labeled-transpose = {
    test-labeled-transpose-carries-the-label = {
      expr = (labeledTranspose diamond).labeledEdges "t";
      expected = [
        {
          label = "e";
          target = "l";
        }
        {
          label = "e";
          target = "r";
        }
      ];
    };
    test-labeled-transpose-CONTROL-forgetting-first-erases-the-label = {
      # the composition this surface replaces: same graph, same run, bare targets —
      # a label regex has nothing to step against
      expr = (transpose (forgetLabels diamond)).edges "t";
      expected = [
        "l"
        "r"
      ];
    };
    test-labeled-transpose-distinguishes-labels-on-parallel-edges = {
      # two labels between the same pair must both survive the reversal
      expr =
        let
          g = labeledFrom {
            nodes = [
              "s"
              "x"
            ];
            perLabel = {
              a = id: if id == "s" then [ "x" ] else [ ];
              b = id: if id == "s" then [ "x" ] else [ ];
            };
          };
        in
        byJson ((labeledTranspose g).labeledEdges "x");
      expected = [
        {
          label = "a";
          target = "s";
        }
        {
          label = "b";
          target = "s";
        }
      ];
    };
    test-labeled-transpose-reverses-direction = {
      expr = {
        source = (labeledTranspose diamond).labeledEdges "s";
        sink = map (e: e.target) ((labeledTranspose diamond).labeledEdges "l");
      };
      expected = {
        source = [ ];
        sink = [ "s" ];
      };
    };
    test-labeled-transpose-preserves-the-node-set = {
      expr = (labeledTranspose labeledFixtures.world).nodes;
      expected = labeledFixtures.world.nodes;
    };
    test-labeled-transpose-is-involutive-on-the-edge-relation = {
      expr = builtins.all (
        n:
        byJson ((labeledTranspose (labeledTranspose labeledFixtures.world)).labeledEdges n)
        == byJson (labeledFixtures.world.labeledEdges n)
      ) labeledFixtures.world.nodes;
      expected = true;
    };
    test-labeled-transpose-serves-the-reverse-read-with-one-construction = {
      # THE POINT: the same query expression, the same follow, the same mode — only
      # the accessor is transposed. Forward from `root` reaches the contained nodes;
      # reverse from `u1` reaches its containers.
      expr = {
        forward = sorted (query {
          graph = labeledFixtures.world;
          from = "root";
          follow = r.plus (r.lit "contains");
          mode = "all";
        });
        reverse = sorted (query {
          graph = labeledTranspose labeledFixtures.world;
          from = "u1";
          follow = r.plus (r.lit "contains");
          mode = "all";
        });
      };
      expected = {
        forward = [
          "h1"
          "h2"
          "u1"
          "u2"
          "vm1"
        ];
        reverse = [
          "h1"
          "root"
        ];
      };
    };
    test-labeled-transpose-does-not-cross-labels = {
      # reversing `member` must not make `contains` reachable from the same root
      expr = sorted (query {
        graph = labeledTranspose labeledFixtures.world;
        from = "u1";
        follow = r.plus (r.lit "member");
        mode = "all";
      });
      expected = [ "g1" ];
    };
    test-labeled-transpose-cycle-terminates = {
      expr = sorted (query {
        graph = labeledTranspose labeledFixtures.cyclic;
        from = "m";
        follow = r.parse "member contains*";
        mode = "all";
      });
      expected = [
        "a"
        "b"
      ];
    };
    test-labeled-transpose-node-with-no-in-edges = {
      expr = (labeledTranspose labeledFixtures.world).labeledEdges "root";
      expected = [ ];
    };
  };
}
