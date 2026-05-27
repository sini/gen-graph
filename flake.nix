{
  description = "gen-graph: accessor-based graph query combinators";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { nixpkgs, ... }:
    {
      lib = import ./. { lib = nixpkgs.lib; };
      __functor = _: import ./.;
    };
}
