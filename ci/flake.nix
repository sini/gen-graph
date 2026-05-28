{
  inputs = {
    gen.url = "github:sini/gen";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.follows = "gen/flake-parts";
    flake-root.follows = "gen/flake-root";
    nix-unit.follows = "gen/nix-unit";
    treefmt-nix.follows = "gen/treefmt-nix";
    devshell.follows = "gen/devshell";
    import-tree.follows = "gen/import-tree";
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
