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
      extraModules = [
        ./tests-error.nix
        # The resolution surfaces the one calculus retired (den-hoag-gayc D16): each is a TOMBSTONE
        # (`lib/default.nix`), so `checks.root-surface` excludes it from the walk, and the generated
        # `root-surface-retired.test-retired-<name>` cell pins this exact message at the root seam —
        # a resurrected or reworded tombstone reds.
        {
          gen.ci.rootSurface.retired = {
            boundedBy = "gen-graph: `boundedBy` is retired. Boundary marks are read inside gen-scope's `resolve`: each node of the evaluation declares `marks`, a stated `bound` narrows further, and the result's `withheld` names every edge a mark withheld on the walk, at the scopes `resolve` reached. A graph-total `withheld` (an edge withheld at a node the walk never visited) is not answered.";
            labeledFrom = "gen-graph: `labeledFrom` is retired. A graph to resolve over is lifted into a gen-scope evaluated scope and walked by `resolve`; a labeled record kept as data for `forgetLabels`, `labeledTranspose` or `cyclicEdgesWhere` is written by hand, `{ nodes = [ … ]; labeledEdges = id: [ { label; target; } … ]; }`.";
            query = "gen-graph: `query` is retired. Resolution is gen-scope's one calculus over an evaluated scope: `resolve { wf = wellFormed { alphabet = [ … ]; expression = \"…\"; }; mode = \"reachable\"; dataFilter = f; } self id` — modes `all` / `paths` / `visible` are `reachable` / `witnesses` / `visible`, and a `where` predicate `p` is `dataFilter = n: if p n then true else null`. Every evaluation `resolve` reads declares `marks` (`_: _: [ ]` states none).";
            regex = "gen-graph: `regex` is retired. A label expression is gen-scope's `wellFormed { alphabet; expression; }`, written as a string or built by the published constructors `wfl` (`lit`, `seq`, `alt`, `star`, `opt`, `plus`, `any`); the derivative engine is not published.";
          };
        }
      ];
    };
}
