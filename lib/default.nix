{ lib, engine ? null }:
let
  sets = import ./sets.nix { inherit lib; };
  combinators = import ./combinators.nix { inherit lib sets; };
  primitives = import ./primitives.nix { inherit lib sets combinators engine; };
in
sets // combinators // primitives
