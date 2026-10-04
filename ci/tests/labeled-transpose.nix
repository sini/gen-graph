# ── THE LABELED TRANSPOSE ───────────────────────────────────────────────────────
# The claim is not that a reverse index exists — `global.nix` has had one — but that
# the reverse read CARRIES THE LABEL. The control that makes the claim mean anything is
# the composition it replaces: forgetting the labels and transposing the plain accessor,
# which answers with bare targets and has nothing left for a label to be read from.
{ genGraph, ... }:
let
  inherit (genGraph)
    labeledFixtures
    labeledTranspose
    forgetLabels
    transpose
    ;
  byJson = builtins.sort (a: b: builtins.toJSON a < builtins.toJSON b);

  # s —e→ l, s —e→ r, l —e→ t, r —e→ t, written as data.
  diamond = {
    nodes = [
      "l"
      "r"
      "s"
      "t"
    ];
    labeledEdges =
      id:
      map
        (target: {
          label = "e";
          inherit target;
        })
        (
          {
            s = [
              "l"
              "r"
            ];
            l = [ "t" ];
            r = [ "t" ];
          }
          .${id} or [ ]
        );
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
      # no label is left to read
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
          g = {
            nodes = [
              "s"
              "x"
            ];
            labeledEdges =
              id:
              if id == "s" then
                [
                  {
                    label = "a";
                    target = "x";
                  }
                  {
                    label = "b";
                    target = "x";
                  }
                ]
              else
                [ ];
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
    test-labeled-transpose-node-with-no-in-edges = {
      expr = (labeledTranspose labeledFixtures.world).labeledEdges "root";
      expected = [ ];
    };
  };
}
