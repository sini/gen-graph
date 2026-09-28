{ prelude }:
let
  traverse = import ./traverse.nix { inherit prelude; };
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
  # `threaded` is each file's R6 primitives by `who` (`key.nix`), and `cores` its doors' unchecked
  # cores (P2 §p2.3.2), both for the doors of another file; neither is published.
  published =
    m:
    builtins.removeAttrs m [
      "threaded"
      "cores"
    ];
in
published traverse
// published global
// published enumerate
// published edgeMaps
// published fixpoint
// published registry
// published declaredEdges
// published endpoints
// published order
// published partition
// published preorder
// published queryLib
// {
  inherit regex;
}
