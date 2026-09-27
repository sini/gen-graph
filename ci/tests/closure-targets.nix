# A NON-STRING TARGET IS REFUSED BEFORE THE CLOSURE COMPARES IT (den-hoag-3w9e7, den-hoag-7gp66
# OQ13 arm a, ADR-0025 item 1). The genericClosure doors made every target of an `edges` result a
# closure key, and the closure's comparison of two differently-typed keys with a string aborts past
# `builtins.tryEval`. They now send such a target through `identifier`: a set, list, function or
# null was already refused this way; OQ13's reading (a node id is a string) closes the scalar
# residue the same way, so an int, bool or float target is refused too. The message cells live on
# `testsError` (`closure-targets`). This file holds what an error cell cannot say: that the refusal
# is a throw `tryEval` observes, and that a string answers as before.
{ genGraph, ... }:
let
  G = genGraph;
  good =
    id:
    if id == "a" then
      [ "b" ]
    else if id == "b" then
      [
        "a"
        "c"
      ]
    else
      [ ];
  acc = e: {
    edges = e;
    nodes = [
      "a"
      "b"
      "c"
    ];
  };
  # every door whose walk is a `genericClosure` over caller targets, and the doors reached through one
  surfaces = e: {
    reachableFrom = G.reachableFrom (acc e) "a";
    reachableWhere = G.reachableWhere (acc e) "a" (_: true);
    canReach = G.canReach (acc e) "a" "c";
    selfReachable = G.selfReachable (acc e) "a";
    reachableVia = G.reachableVia (G.hoistEdges (acc e)) "a";
    selfReachableVia = G.selfReachableVia (G.hoistEdges (acc e)) "a";
    coScc = G.coScc (acc e) "a" "c";
    fromRegistryDown = G.reachableFrom (G.fromRegistry {
      registry = {
        a = { };
        b = { };
        c = { };
      };
      edges = id: _entry: e id;
    }) "a";
  };
  # Every shape `identifier` refuses a target for: the 4 non-scalar shapes (den-hoag-3w9e7) plus the
  # 3 scalars OQ13 closed (den-hoag-7gp66 arm a) — everything but a string.
  notAString = {
    set = { };
    list = [ ];
    function = x: x;
    null = null;
    int = 1;
    bool = true;
    float = 1.5;
  };
  # b's edges hold the bad target beside a string, so the closure has a string to compare it with
  at = v: id: if id == "b" then [ v ] else good id;
  caught = v: builtins.tryEval (builtins.deepSeq v true);
  refused = {
    success = false;
    value = false;
  };
in
{
  flake.tests.closure-targets =
    builtins.listToAttrs (
      map (s: {
        name = "test-${s}-refuses-a-non-string-target-catchably";
        value = {
          expr = builtins.mapAttrs (_: v: caught (surfaces (at v)).${s}) notAString;
          expected = builtins.mapAttrs (_: _: refused) notAString;
        };
      }) (builtins.attrNames (surfaces good))
    )
    // {
      # CONTROL: the lawful accessor answers every surface as before, so the refusals are the guard
      test-a-string-target-still-answers = {
        expr = surfaces good;
        expected = {
          reachableFrom = [
            "b"
            "c"
          ];
          reachableWhere = [
            "b"
            "c"
          ];
          canReach = true;
          selfReachable = true;
          reachableVia = [
            "b"
            "c"
          ];
          selfReachableVia = true;
          coScc = false;
          fromRegistryDown = [
            "b"
            "c"
          ];
        };
      };
    };
}
