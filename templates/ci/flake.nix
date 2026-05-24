{
  inputs = {
    gen-graph.url = "github:sini/gen-graph";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { gen-graph, nixpkgs, nix-unit, ... }:
    let
      lib = nixpkgs.lib;
      graphLib = gen-graph { inherit lib; };
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      testFiles = lib.pipe (builtins.readDir ./tests) [
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n))
        builtins.attrNames
      ];
      tests = lib.foldl' (
        acc: file: acc // (import ./tests/${file} { inherit lib graphLib; })
      ) {} testFiles;
    in {
      inherit tests;
      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
            assertTests = lib.mapAttrsToList (suite: subtests:
              lib.mapAttrsToList (name: t:
                if t.expr == t.expected then true
                else throw "FAIL ${suite}.${name}: got ${builtins.toJSON t.expr}, expected ${builtins.toJSON t.expected}"
              ) subtests
            ) tests;
        in {
          nix-unit = pkgs.runCommand "gen-graph-tests" {} ''
            echo "${builtins.toJSON (builtins.length (lib.flatten assertTests))} tests passed"
            touch $out
          '';
        }
      );
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { default = pkgs.mkShell { packages = [ nix-unit.packages.${system}.default ]; }; }
      );
    };
}
