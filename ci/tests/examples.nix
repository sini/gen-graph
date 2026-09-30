{ lib, ... }:
{
  gen.ci.examples.demo = (import ../../examples/demo/flake.nix).outputs {
    nixpkgs.lib = lib;
  };
}
