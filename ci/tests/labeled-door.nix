# ── THE ACCESSOR'S RESULT IS REFUSED WHERE IT IS READ ───────────────────────────
# A labeled graph is a structural record, so `labeledEdges` is a caller-supplied function and
# every surface applying it receives a value it did not construct. Unguarded, a malformed result
# either aborted past `tryEval` at the read or was admitted without refusal at exit 0. These cells
# assert the refusal is CATCHABLE on every arm through every surface that reads it; the message
# is asserted on `testsError` (`ci/tests-error.nix`, `labeled-door`), the only output that can.
#
# ★ THE NO-EARLIER CELL is the one that decides the construction. A field is checked where the
# surface reads it and not before, so an edge whose target a surface never reads never has its
# target judged: gen-view lawfully hangs `s —r→ d` edges whose target is a datum. An eager
# whole-result check refuses that graph — measured, den-hoag-vq94z spec §0.5. The walk modes that
# first carried this cell retired with the calculus (den-hoag-gayc U3); `cyclicEdgesWhere` under a
# `p` that reads its label and is never true reads every label and no target, which is the same
# discriminator.
{ genGraph, ... }:
let
  inherit (genGraph)
    cyclicEdgesWhere
    forgetLabels
    labeledTranspose
    ;

  # every malformed arm is hung on node `a`; `b` is well formed
  arms = {
    notList =
      id:
      if id == "a" then
        {
          label = "x";
          target = "b";
        }
      else
        [ ];
    bareTarget = id: if id == "a" then [ "b" ] else [ ];
    noLabel = id: if id == "a" then [ { target = "b"; } ] else [ ];
    noTarget = id: if id == "a" then [ { label = "x"; } ] else [ ];
    intLabel =
      id:
      if id == "a" then
        [
          {
            label = 1;
            target = "b";
          }
        ]
      else
        [ ];
    intTarget =
      id:
      if id == "a" then
        [
          {
            label = "x";
            target = 1;
          }
        ]
      else
        [ ];
    setTarget =
      id:
      if id == "a" then
        [
          {
            label = "x";
            target = {
              n = "b";
            };
          }
        ]
      else
        [ ];
    # the accessor itself is not a function
    notFunction = [ ];
  };
  control =
    id:
    {
      a = [
        {
          label = "x";
          target = "b";
        }
      ];
    }
    .${id} or [ ];
  # `a —x→ b` and `a —r→ { x = 1; }`: the second edge's target is a datum, lawful while unread
  datum =
    id:
    {
      a = [
        {
          label = "x";
          target = "b";
        }
        {
          label = "r";
          target = {
            x = 1;
          };
        }
      ];
    }
    .${id} or [ ];
  graphOf = labeledEdges: {
    nodes = [
      "a"
      "b"
    ];
    inherit labeledEdges;
  };

  # the graph surfaces that apply the accessor
  surfaces = {
    transpose = g: (labeledTranspose g).labeledEdges "b";
    forget = g: (forgetLabels g).edges "a";
    cyclic = g: cyclicEdgesWhere (_: true) g;
    # every label read, and no target: `p` forces its label and is never true, so the partition
    # is never forced
    labels = g: cyclicEdgesWhere (l: l == "none") g;
  };

  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  # the arms a surface ADMITS; every other arm it refuses catchably, or the cell never returns
  admittedBy =
    run: builtins.filter (arm: admitted (run (graphOf arms.${arm}))) (builtins.attrNames arms);
in
{
  flake.tests.labeled-door = {
    # A surface refuses exactly the arms whose field it reads. `forgetLabels` and
    # `cyclicEdgesWhere` under `_: true` never read a label, so the two label arms pass them, and
    # under `_: false` it reads no target, so the three target arms pass it — the no-earlier
    # clause, not a gap: the refusal arrives at the surface that reads it.
    test-every-graph-surface-refuses-the-arms-it-reads-catchably = {
      expr = builtins.mapAttrs (_: admittedBy) surfaces;
      expected = {
        transpose = [ ];
        forget = [
          "intLabel"
          "noLabel"
        ];
        cyclic = [
          "intLabel"
          "noLabel"
        ];
        labels = [
          "intTarget"
          "noTarget"
          "setTarget"
        ];
      };
    };

    # CONTROL: the well-formed graph's answers, unchanged by the guard
    test-the-well-formed-graph-answers-at-every-surface = {
      expr = builtins.mapAttrs (_: run: run (graphOf control)) surfaces;
      expected = {
        transpose = [
          {
            label = "x";
            target = "a";
          }
        ];
        forget = [ "b" ];
        cyclic = [ ];
        labels = [ ];
      };
    };

    # ★ THE NO-EARLIER CELL. The `r` edge's datum target is never read by a surface that reads
    # only labels, and it answers as it did before the guard existed.
    test-an-unread-datum-target-is-not-refused = {
      expr = surfaces.labels (graphOf datum);
      expected = [ ];
    };
    # …and a surface that DOES read every target at a node refuses the same edge
    test-a-surface-reading-every-target-refuses-the-datum = {
      expr = {
        forget = admitted (surfaces.forget (graphOf datum));
        transpose = admitted (surfaces.transpose (graphOf datum));
      };
      expected = {
        forget = false;
        transpose = false;
      };
    };
  };
}
