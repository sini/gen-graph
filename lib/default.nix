{ lib }:
let
  traverse = import ./traverse.nix { inherit lib; };
  global = import ./global.nix { inherit lib; };
  enumerate = import ./enumerate.nix { inherit lib; };
  edgeMaps = import ./edge-maps.nix { inherit lib; };
  fixpoint = import ./fixpoint.nix { inherit lib; };
  registry = import ./registry.nix { inherit lib; };
in
traverse // global // enumerate // edgeMaps // fixpoint // registry
