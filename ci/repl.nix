# gen-graph REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  genGraph = import ./.. { inherit (nixpkgs) lib; };
in
{
  inherit (nixpkgs) lib;
  inherit genGraph;
}
// genGraph
