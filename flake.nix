{
  description = "gen-graph: accessor-based graph query combinators";

  # gen-graph is nixpkgs-lib-free: the library depends only on gen-prelude (pure,
  # zero-input). It is pure graph/list/attr combinators — no module system, no nixpkgs.lib.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
  };

  outputs =
    { gen-prelude, ... }:
    {
      # ★ THE ROOT, NOT `./lib`. `./.` and `./lib` were two independent constructions of one
      # value and so free to disagree; there is ONE construction site now, and the two entry
      # paths differ only in who supplies the arguments. Here the flake supplies them, so
      # `follows` governs every argument passed, while the standalone path falls back to
      # `ci/flake.lock`.
      lib = import ./. { prelude = gen-prelude.lib; };
    };
}
