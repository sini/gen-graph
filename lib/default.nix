{ prelude }:
let
  traverse = import ./traverse.nix;
  global = import ./global.nix { inherit prelude; };
  enumerate = import ./enumerate.nix { inherit prelude; };
  edgeMaps = import ./edge-maps.nix { inherit prelude; };
  fixpoint = import ./fixpoint.nix { inherit prelude; };
  registry = import ./registry.nix { inherit prelude; };
  order = import ./order.nix { inherit prelude; };
  regex = import ./regex.nix { inherit prelude; };
  queryLib = import ./query.nix { inherit prelude; };
in
traverse
// global
// enumerate
// edgeMaps
// fixpoint
// registry
// order
// queryLib
// {
  inherit regex;
}
