# A NON-SCALAR TARGET IS REFUSED BEFORE THE CLOSURE COMPARES IT (den-hoag-3w9e7, ADR-0025 item 1).
# The genericClosure doors made every target of an `edges` result a closure key, and the closure's
# comparison of a set, list, function or null with a string aborts past `builtins.tryEval`. They
# now send such a target through `nodeKey`. The message cells live on `testsError`
# (`closure-targets`), with the scalar residue pinned `…-pending-OQ13`. This file holds what an
# error cell cannot say: that the refusal is a throw `tryEval` observes, and that a string answers
# as before.
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
  nonScalars = {
    set = { };
    list = [ ];
    function = x: x;
    null = null;
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
        name = "test-${s}-refuses-a-non-scalar-target-catchably";
        value = {
          expr = builtins.mapAttrs (_: v: caught (surfaces (at v)).${s}) nonScalars;
          expected = builtins.mapAttrs (_: _: refused) nonScalars;
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
