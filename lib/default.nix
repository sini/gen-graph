{ prelude }:
let
  traverse = import ./traverse.nix;
  global = import ./global.nix { inherit prelude; };
  enumerate = import ./enumerate.nix { inherit prelude; };
  edgeMaps = import ./edge-maps.nix { inherit prelude; };
  fixpoint = import ./fixpoint.nix { inherit prelude; };
  registry = import ./registry.nix { inherit prelude; };
  declaredEdges = import ./declared-edges.nix { inherit prelude; };
  endpoints = import ./endpoints.nix { inherit prelude; };
  order = import ./order.nix { inherit prelude; };
  partition = import ./partition.nix { inherit prelude; };
  preorder = import ./preorder.nix { inherit prelude; };
  regex = import ./regex.nix { inherit prelude; };
  queryLib = import ./query.nix { inherit prelude; };
in
# `threaded` is each file's R6 primitives by `who` (`key.nix`), for the doors of another file; it is
# not published.
builtins.removeAttrs traverse [ "threaded" ]
// global
// enumerate
// builtins.removeAttrs edgeMaps [ "threaded" ]
// fixpoint
// registry
// declaredEdges
// endpoints
// order
// builtins.removeAttrs partition [ "threaded" ]
// preorder
// queryLib
// {
  inherit regex;
}
