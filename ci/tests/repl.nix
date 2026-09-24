# The repl entry (`ci/repl.nix`, the harness `repl` command's file) loads, and loads exactly the
# library surface plus `lib` and `genGraph`. Nothing else in the suite reaches that file, which is
# how it came to call the nullary root with an argument it never declared (den-hoag-s34cm).
{
  lib,
  genGraph,
  genPrelude,
  ...
}:
{
  flake.tests.repl.test-entry-loads-the-surface = {
    expr = builtins.attrNames (
      import ../repl.nix {
        inherit lib;
        prelude = genPrelude;
      }
    );
    expected = builtins.attrNames ({ inherit lib genGraph; } // genGraph);
  };
}
