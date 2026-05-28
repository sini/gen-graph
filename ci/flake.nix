{
  inputs = {
    gen.url = "github:sini/gen";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      graphLib = import ../. { inherit lib; };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-graph";
      testModules = ./tests;
      specialArgs = { inherit graphLib; };
    };
}
