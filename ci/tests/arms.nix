# The ordering ARM against the ordering DOOR, on the generated shapes.
#
# `topoOrderKahn` is A. B. Kahn 1962 published under its own name; `topoOrder` is the door
# and today delegates to it. The door's default is a separate decision from the arm's
# identity — that separation is the whole point of the name — so the agreement between them
# is a property to be measured at every revision rather than read off today's one-line
# delegation. `coneRank` binds the ARM, so a caller reading the door's order and a caller
# reading the arm's must see the same sequence for as long as the door delegates.
#
# ELEMENT-WISE, never a summary. `{ first, last, len }` agreement is not agreement: two
# valid topological orders over the same graph share all three and differ at index 1 (the
# measurement `den-hoag-nz21` records on `fleet`/`discrim`). Every cell below compares the
# whole emitted list by value.
#
# The shapes are the bench's, verbatim, so a figure measured in `ci/bench/cost-classes.nix`
# and a verdict asserted here are about the same graphs.
{ genGraph, ... }:
let
  inherit (genGraph)
    topoOrder
    topoOrderKahn
    ;

  ix = m: builtins.genList (i: i) m;
  key = p: i: p + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000" + toString i;
  fromPairs = ns: pairs: {
    nodes = ns;
    edges =
      let
        m = builtins.listToAttrs pairs;
      in
      k: m.${k} or [ ];
  };

  # node i depends on i-1: one legal order, keys ascending with depth.
  chain =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
  # `chain` with the edge direction flipped and nothing else changed, so the keys now
  # ascend AGAINST the dependency order. The sentinel node moves from the head to the
  # tail — it has to, or the last node would name a dependency outside `nodes`, which is a
  # refusal rather than a shape.
  chainRev =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == n - 1 then [ ] else [ (key "n" (i + 1)) ];
      }) (ix n)
    );
  # n/10 independent 10-chains: the shape a host fleet produces.
  fleet =
    n:
    let
      c = n / 10;
      k =
        i: d:
        "h"
        + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000"
        + toString i
        + "-"
        + toString d;
    in
    fromPairs (builtins.concatLists (map (i: map (k i) (ix 10)) (ix c))) (
      builtins.concatLists (
        map (
          i:
          map (d: {
            name = k i d;
            value = if d == 0 then [ ] else [ (k i (d - 1)) ];
          }) (ix 10)
        ) (ix c)
      )
    );
  # n/2 ready at the start, each releasing one whose key sorts BELOW every node still
  # waiting: the shape on which two different valid topological orders are distinguishable.
  discrim =
    n:
    let
      m = n / 2;
    in
    fromPairs (map (key "m") (ix m) ++ map (key "a") (ix m)) (
      map (i: {
        name = key "a" i;
        value = [ (key "m" i) ];
      }) (ix m)
    );
  # one 4000-node chain PLUS (n-4000)/2 independent 2-chains: depth and width additive.
  deepwide =
    n:
    let
      d = 4000;
      m = (n - d) / 2;
    in
    fromPairs (map (key "c") (ix d) ++ map (key "a") (ix m) ++ map (key "b") (ix m)) (
      map (i: {
        name = key "c" i;
        value = if i == 0 then [ ] else [ (key "c" (i - 1)) ];
      }) (ix d)
      ++ map (i: {
        name = key "b" i;
        value = [ (key "a" i) ];
      }) (ix m)
    );

  # Small enough to run in a suite, large enough that the two arms could diverge anywhere
  # in 300 emissions rather than in a handful.
  small = 300;
  shapes = {
    chain = chain small;
    chainRev = chainRev small;
    fleet = fleet small;
    discrim = discrim small;
    deepwide = deepwide 4002;
  };

  doorOrder = fx: (topoOrder fx).order;
  armOrder = fx: (topoOrderKahn fx).order;
  reversed =
    xs: builtins.genList (i: builtins.elemAt xs (builtins.length xs - 1 - i)) (builtins.length xs);
in
{
  flake.tests.arms = {
    # ── door ≡ arm, element-wise, one cell per shape ──
    test-arm-door-chain = {
      expr = doorOrder shapes.chain;
      expected = armOrder shapes.chain;
    };
    test-arm-door-chain-rev = {
      expr = doorOrder shapes.chainRev;
      expected = armOrder shapes.chainRev;
    };
    test-arm-door-fleet = {
      expr = doorOrder shapes.fleet;
      expected = armOrder shapes.fleet;
    };
    test-arm-door-discrim = {
      expr = doorOrder shapes.discrim;
      expected = armOrder shapes.discrim;
    };
    test-arm-door-deepwide = {
      expr = doorOrder shapes.deepwide;
      expected = armOrder shapes.deepwide;
    };

    # ARMED CONTROL. If the comparison above could not separate two orders it would agree
    # with anything, including a reversal — which is a valid topological order of NO shape
    # here (each has at least one edge, and reversing puts a consumer before its producer).
    # A `false` on every shape is what makes the agreement cells load-bearing.
    test-arm-door-reversal-control = {
      expr = builtins.mapAttrs (_: fx: doorOrder fx == reversed (armOrder fx)) shapes;
      expected = builtins.mapAttrs (_: _: false) shapes;
    };

    # ── the arm is a live surface, called by name ──
    # Not reached through the door in any of these: a name that only ever runs because
    # something else delegates to it is not published.
    test-arm-direct-order = {
      expr =
        (topoOrderKahn {
          nodes = [
            "a"
            "b"
            "c"
          ];
          edges =
            id:
            {
              a = [ "b" ];
              b = [ "c" ];
            }
            .${id} or [ ];
        }).order;
      expected = [
        "c"
        "b"
        "a"
      ];
    };
    # The cycle report is the arm's too, not a wrapper's.
    test-arm-direct-cycle-report = {
      expr =
        let
          r = topoOrderKahn {
            nodes = [
              "a"
              "b"
            ];
            edges =
              id:
              {
                a = [ "b" ];
                b = [ "a" ];
              }
              .${id} or [ ];
          };
        in
        {
          inherit (r) ok;
          cycles = r.cycles;
        };
      expected = {
        ok = false;
        cycles = [
          [
            "a"
            "b"
          ]
        ];
      };
    };
    # And the refusals: the arm carries them, so binding it by name loses no guard.
    test-arm-direct-refuses-dangling = {
      expr =
        !(builtins.tryEval (
          builtins.deepSeq (topoOrderKahn {
            nodes = [ "a" ];
            edges = _: [ "ghost" ];
          }) true
        )).success;
      expected = true;
    };
    # LIVE CONTROL for the refusal cell above, same run: a well-formed call is not caught.
    test-arm-direct-refusal-control = {
      expr =
        !(builtins.tryEval (
          builtins.deepSeq (topoOrderKahn {
            nodes = [ "a" ];
            edges = _: [ ];
          }) true
        )).success;
      expected = false;
    };
  };
}
