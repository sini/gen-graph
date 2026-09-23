# ── THE ACCESSOR'S RESULT IS REFUSED WHERE IT IS READ ───────────────────────────
# A labeled graph is a structural record, so `labeledEdges` is a caller-supplied function and
# every surface applying it receives a value it did not construct. Unguarded, a malformed result
# either aborted past `tryEval` at the read or — an int label never equals a literal, `series`
# answers a non-string target as a node — was admitted without refusal at exit 0. These cells
# assert the refusal is CATCHABLE on every arm through every surface that reads it; the message
# is asserted on `testsError` (`ci/tests-error.nix`, `labeled-door`), the only output that can.
#
# ★ THE NO-EARLIER CELL is the one that decides the construction. A field is checked where the
# surface reads it and not before, so an edge a walk prunes on its label never has its target
# judged: gen-view lawfully hangs `s —r→ d` edges whose target is a datum on nodes an `x*` walk
# visits. An eager whole-result check refuses that graph, and no other suite here or in gen-view
# notices — measured, den-hoag-vq94z spec §0.5.
{ genGraph, ... }:
let
  inherit (genGraph)
    boundedBy
    cyclicEdgesWhere
    forgetLabels
    labeledTranspose
    query
    queryArrivals
    regex
    ;
  x = regex.star (regex.lit "x");
  anyStar = regex.star regex.any;

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

  walk =
    mode: follow: graph:
    if mode == "arrivals" then
      queryArrivals {
        inherit graph follow;
        from = "a";
        advance = s: s.distance + 1;
      }
    else if mode == "visible" then
      query {
        inherit mode graph follow;
        from = "a";
        groupBy = a: a.node;
      }
    else if mode == "fixpoint" then
      query {
        inherit mode graph follow;
        from = "a";
        empty = [ ];
        combine = a: b: a ++ [ b ];
      }
    else
      query {
        inherit mode graph follow;
        from = "a";
      };
  # each walk mode under `x*`, plus `all` under `any*` — `regex.deriv` on `any` never reads
  # its letter, so that column is what shows the walk forces the label itself
  modes = {
    all = walk "all" x;
    series = walk "series" x;
    paths = walk "paths" x;
    visible = walk "visible" x;
    layers = walk "layers" x;
    fixpoint = walk "fixpoint" x;
    arrivals = walk "arrivals" x;
    anyAll = walk "all" anyStar;
  };
  # the graph surfaces that apply the accessor outside a walk, and gen-view's composed shape
  # (`query ∘ boundedBy ∘ labeledTranspose`, `gen-view/lib/relation.nix`)
  surfaces = {
    bounded =
      g:
      query {
        graph = boundedBy g (_: [
          {
            name = "m";
            admits = _: true;
          }
        ]);
        from = "a";
        follow = x;
      };
    composed =
      g:
      query {
        graph = boundedBy (labeledTranspose g) (_: [ ]);
        from = "b";
        follow = x;
      };
    composedAny =
      g:
      query {
        graph = boundedBy (labeledTranspose g) (_: [ ]);
        from = "b";
        follow = anyStar;
      };
    transpose = g: (labeledTranspose g).labeledEdges "b";
    forget = g: (forgetLabels g).edges "a";
    cyclic = g: cyclicEdgesWhere g (_: true);
  };

  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  # the arms a surface ADMITS; every other arm it refuses catchably, or the cell never returns
  admittedBy =
    run: builtins.filter (arm: admitted (run (graphOf arms.${arm}))) (builtins.attrNames arms);
  valuesUnder = graph: builtins.mapAttrs (_: run: run graph) modes;
in
{
  flake.tests.labeled-door = {
    test-every-walk-mode-refuses-every-malformed-arm-catchably = {
      expr = builtins.mapAttrs (_: admittedBy) modes;
      expected = builtins.mapAttrs (_: _: [ ]) modes;
    };

    # A surface refuses exactly the arms whose field it reads. `forgetLabels` and
    # `cyclicEdgesWhere` under `_: true` never read a label, so the two label arms pass them —
    # the no-earlier clause, not a gap: the refusal arrives at the surface that reads it.
    test-every-graph-surface-refuses-the-arms-it-reads-catchably = {
      expr = builtins.mapAttrs (_: admittedBy) surfaces;
      expected = {
        bounded = [ ];
        composed = [ ];
        composedAny = [ ];
        transpose = [ ];
        forget = [
          "intLabel"
          "noLabel"
        ];
        cyclic = [
          "intLabel"
          "noLabel"
        ];
      };
    };

    # CONTROL: the well-formed graph's answers, unchanged by the guard
    test-the-well-formed-graph-answers-in-every-mode = {
      expr = valuesUnder (graphOf control);
      expected = {
        all = [
          "a"
          "b"
        ];
        anyAll = [
          "a"
          "b"
        ];
        arrivals = [
          {
            admission = "'x*";
            distance = 0;
            node = "a";
            via = null;
          }
          {
            admission = "'x*";
            distance = 1;
            node = "b";
            via = {
              from = "a";
              label = "x";
            };
          }
        ];
        fixpoint = [
          "a"
          "b"
        ];
        layers = [
          [
            {
              node = "a";
              path = [ ];
            }
          ]
          [
            {
              node = "b";
              path = [
                {
                  from = "a";
                  label = "x";
                  to = "b";
                }
              ];
            }
          ]
        ];
        paths = [
          {
            node = "a";
            path = [ ];
          }
          {
            node = "b";
            path = [
              {
                from = "a";
                label = "x";
                to = "b";
              }
            ];
          }
        ];
        series = [
          "a"
          "b"
        ];
        visible = {
          shadowed = [ ];
          visible = [
            {
              node = "a";
              path = [ ];
            }
            {
              node = "b";
              path = [
                {
                  from = "a";
                  label = "x";
                  to = "b";
                }
              ];
            }
          ];
        };
      };
    };

    # ★ THE NO-EARLIER CELL. The `r` edge is pruned on its label, so its datum target is never
    # read, and the walk answers as it did before the guard existed.
    test-an-unfollowed-datum-target-is-not-refused = {
      expr = {
        all = walk "all" x (graphOf datum);
        series = walk "series" x (graphOf datum);
        paths = map (a: a.node) (walk "paths" x (graphOf datum));
      };
      expected = {
        all = [
          "a"
          "b"
        ];
        series = [
          "a"
          "b"
        ];
        paths = [
          "a"
          "b"
        ];
      };
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
