{
  description = "gen-graph: monotonic query combinators over scope graphs";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    lib = import ./. { lib = nixpkgs.lib; };
    __functor = _: import ./.;
  };
}
