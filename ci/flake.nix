{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    # nixpkgs is the CI runner's dependency (test harness, treefmt) and supplies the
    # `lib` the test modules use. The library itself (../lib) takes only gen-prelude.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen-harness,
      gen-prelude,
      ...
    }:
    let
      prelude = import "${gen-prelude}/lib";
      genGraph = import ../lib { inherit prelude; };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-graph";
      # `testModules` is the whole of `flake.tests`, and `flake.tests` is the whole of what
      # the batch asserter behind `checks.default` quantifies over. Cells that assert an
      # ERROR cannot live there — the asserter forces `expr` unconditionally, so a throwing
      # `expr` crashes the gate rather than failing a cell. They are therefore outside this
      # tree by construction, on their own output: `./tests-error.nix`, read by
      # `nix-unit --flake ./ci#testsError`.
      testModules = ./tests;
      # The harness's own `genPrelude` carries `hasInfix` and nothing else. Three suites here
      # (arms, partition, topo) take `genPrelude` as the WHOLE prelude and build graphs with it,
      # so that reach is gen-graph's and is supplied from gen-graph's own gen-prelude pin — the
      # same instance `genGraph` above was built from, so the suites and the library under test
      # share one build of the prelude rather than holding two.
      specialArgs = {
        inherit genGraph;
        genPrelude = prelude;
      };
      extraModules = [ ./tests-error.nix ];
    };
}
