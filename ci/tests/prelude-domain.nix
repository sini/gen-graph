# THE DEDUP'S DOMAIN, AS A CONTRACT GATE.
#
# `prelude.unique` is the dedup five call sites in `lib/` depend on — `edge-maps.materialize`
# and `unionEdges`, `fixpoint`'s closure step, `query`'s labeled edges and `registry`'s edge
# index — and gen-graph hands it node ids, which are strings.
#
# ★ THE CONTRACT IS TOTALITY, AND THE STRING PATH IS AN OPTIMIZATION RATHER THAN A DOMAIN
# RESTRICTION. The binding has two paths: an all-string list is deduped by sorting
# FIRST-OCCURRENCE INDICES, and everything else falls back to a `foldl'` with `elem`. Those are
# two implementations of ONE function. `unique` is total on lists — every element type, mixed
# types, the empty list and the singleton — and a narrowing of that domain is a breaking change
# to this library whether or not gen-graph's own call sites would notice it today.
#
# ★★ WHY THIS SUITE EXISTS RATHER THAN A SCRATCHPAD PROBE. A locally re-derived dedup is an
# attractive optimization and has been proposed before; one such candidate was TOTAL ON STRINGS
# and aborted on eight of the ten classes below, which is invisible to any corpus built from
# node ids. A probe can catch that once. Only a cell in CI can stop it landing quietly, and the
# clause this suite discharges is precisely "keep the cell even though the shipped binding
# passes it trivially".
#
# ★ ON `tryEval`, MEASURED RATHER THAN ASSUMED: it does NOT contain the failure mode this suite
# is aimed at. The candidate above aborted with a non-zero exit and no output through a
# `tryEval` wrapper — the abort escaped it. That is why the cells below assert VALUES: a wrong
# answer fails its cell, a catchable throw surfaces as an error cell, and an uncatchable abort
# takes the whole runner down. All three are loud, which is the property being bought here.
# The totality cell at the end states the contract as one proposition rather than leaving it
# implied by ten unrelated equalities.
{ genPrelude, ... }:
let
  inherit (genPrelude) unique;

  # The ten input classes. `string` is the live positive control: if a future binding broke the
  # path gen-graph actually uses, this row fails first and the rest are diagnosis.
  cases = {
    string = [
      "b"
      "a"
      "b"
    ];
    empty = [ ];
    singleton = [ 42 ];
    int = [
      3
      1
      3
      2
      1
    ];
    bool = [
      true
      false
      true
    ];
    attrs = [
      { a = 1; }
      { b = 2; }
      { a = 1; }
    ];
    list = [
      [ 1 ]
      [ 2 ]
      [ 1 ]
    ];
    null = [
      null
      null
    ];
    mixed = [
      "a"
      1
      "a"
    ];
    float = [
      1.5
      2.5
      1.5
    ];
  };
in
{
  flake.tests.prelude-domain = {
    # ── ONE CELL PER CLASS, ASSERTING THE VALUE ──
    # Read from the binding rather than predicted from it: a fixture written to agree with an
    # assumption agrees with nothing.
    test-unique-string-control = {
      expr = unique cases.string;
      expected = [
        "b"
        "a"
      ];
    };
    test-unique-empty = {
      expr = unique cases.empty;
      expected = [ ];
    };
    test-unique-singleton = {
      expr = unique cases.singleton;
      expected = [ 42 ];
    };
    test-unique-int = {
      expr = unique cases.int;
      expected = [
        3
        1
        2
      ];
    };
    test-unique-bool = {
      expr = unique cases.bool;
      expected = [
        true
        false
      ];
    };
    test-unique-attrs = {
      expr = unique cases.attrs;
      expected = [
        { a = 1; }
        { b = 2; }
      ];
    };
    test-unique-list = {
      expr = unique cases.list;
      expected = [
        [ 1 ]
        [ 2 ]
      ];
    };
    test-unique-null = {
      expr = unique cases.null;
      expected = [ null ];
    };
    test-unique-mixed = {
      expr = unique cases.mixed;
      expected = [
        "a"
        1
      ];
    };
    test-unique-float = {
      expr = unique cases.float;
      expected = [
        1.5
        2.5
      ];
    };

    # ── THE ORDER THE STRING PATH KEEPS, WHICH IS THE THING IT IS EASIEST TO GET WRONG ──
    # It sorts INDICES, not values, so the answer comes back in first-occurrence order. A
    # re-derivation that sorted the values instead would be correct as a SET and wrong here,
    # and every downstream ordered output — the condensation's edge lists, the closure's rows —
    # would quietly change with it. Both inputs are in descending order, so a sorted-output
    # dedup returns the reverse of what these cells assert and cannot pass by coincidence.
    test-unique-keeps-first-occurrence-order = {
      expr = unique [
        "z"
        "m"
        "a"
        "m"
        "z"
      ];
      expected = [
        "z"
        "m"
        "a"
      ];
    };
    test-unique-string-path-does-not-return-sorted-output = {
      expr = unique [
        "d"
        "c"
        "b"
        "a"
        "d"
        "c"
        "b"
        "a"
      ];
      expected = [
        "d"
        "c"
        "b"
        "a"
      ];
    };

    # ── TOTALITY, AS ONE PROPOSITION ──
    # `deepSeq` forces each result so a lazily-deferred failure cannot pass as a success. This
    # cell cannot see an abort that escapes `tryEval` — measured, and stated at the top — but it
    # is what makes "total on lists" a claim this suite asserts rather than one a reader infers.
    test-unique-is-total-on-every-class = {
      expr = builtins.mapAttrs (
        _name: xs: (builtins.tryEval (builtins.deepSeq (unique xs) true)).success
      ) cases;
      expected = builtins.mapAttrs (_name: _: true) cases;
    };
  };
}
