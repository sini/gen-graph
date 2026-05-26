# gen-graph REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  graphLib = import ./.. { inherit (nixpkgs) lib; };
in
{
  inherit (nixpkgs) lib;
  inherit graphLib;
}
// graphLib
