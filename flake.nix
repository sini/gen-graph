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
      lib = import ./lib { prelude = gen-prelude.lib; };
    };
}
