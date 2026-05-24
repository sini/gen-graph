{ lib }:
let
  sets = import ./sets.nix { inherit lib; };
  combinators = import ./combinators.nix { inherit lib sets; };
  primitives = import ./primitives.nix { inherit lib sets combinators; };
  mock = import ./mock.nix { inherit lib; };
in
sets // combinators // primitives // { inherit mock; }
