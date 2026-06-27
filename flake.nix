{
  description = "gen-graph: accessor-based graph query combinators";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { nixpkgs, ... }:
    {
      lib = import ./lib { lib = nixpkgs.lib; };
    };
}
