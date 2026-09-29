{ lib, genGraph, ... }:
{
  gen.ci.examples.demo = (import ../../examples/demo/flake.nix).outputs {
    gen-graph.lib = genGraph;
    nixpkgs.lib = lib;
  };
}
