{ lib, engine ? null }:
let
  sets = import ./sets.nix { inherit lib; };
  combinators = import ./combinators.nix { inherit lib sets; };
in
sets // combinators
