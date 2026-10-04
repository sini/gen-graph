{ prelude }:
let
  traverse = import ./traverse.nix { inherit prelude; };
  global = import ./global.nix { inherit prelude; };
  enumerate = import ./enumerate.nix { inherit prelude; };
  edgeMaps = import ./edge-maps.nix { inherit prelude; };
  fixpoint = import ./fixpoint.nix { inherit prelude; };
  registry = import ./registry.nix { inherit prelude; };
  declaredEdges = import ./declared-edges.nix { inherit prelude; };
  endpoints = import ./endpoints.nix { inherit prelude; };
  order = import ./order.nix { inherit prelude; };
  partition = import ./partition.nix { inherit prelude; };
  preorder = import ./preorder.nix { inherit prelude; };
  # `threaded` is each file's R6 primitives by `who` (`key.nix`), and `cores` its doors' unchecked
  # cores (P2 §p2.3.2), both for the doors of another file; neither is published.
  published =
    m:
    builtins.removeAttrs m [
      "threaded"
      "cores"
    ];
in
published traverse
// published global
// published enumerate
// published edgeMaps
// published fixpoint
// published registry
// published declaredEdges
// published endpoints
// published order
// published partition
// published preorder
// {
  # The refusal machinery every door above applies with `"gen-graph"` (den-hoag-gayc U1a): a plain
  # function of `prefix`, so another library reaches the SAME module applied to its own name
  # (`key "gen-scope"`) rather than a second key former. Unapplied here — a caller supplies its own
  # prefix; `published`'s `threaded`/`cores` strip does not apply to a function.
  key = import ./key.nix;
  # RETIRED BY THE ONE CALCULUS (den-hoag-gayc D16; ADR-0008): resolution is gen-scope's `resolve`
  # over an evaluated scope, and this library keeps the classical half. Each name is a tombstone
  # naming its replacement, so an un-migrated call is refused where it is written rather than
  # answering. `series`, `layers`, the `fixpoint` mode (the classical `fixpoint` stays), `queryFold`, `queryArrivals`, `valueOf` and the rank
  # helpers had no caller and are dropped without one.
  query = throw "gen-graph: `query` is retired. Resolution is gen-scope's one calculus over an evaluated scope: `resolve { wf = wellFormed { alphabet = [ … ]; expression = \"…\"; }; mode = \"reachable\"; dataFilter = f; } self id` — modes `all` / `paths` / `visible` are `reachable` / `witnesses` / `visible`, and a `where` predicate `p` is `dataFilter = n: if p n then true else null`. Every evaluation `resolve` reads declares `marks` (`_: _: [ ]` states none).";
  regex = throw "gen-graph: `regex` is retired. A label expression is gen-scope's `wellFormed { alphabet; expression; }`, written as a string or built by the published constructors `wfl` (`lit`, `seq`, `alt`, `star`, `opt`, `plus`, `any`); the derivative engine is not published.";
  labeledFrom = throw "gen-graph: `labeledFrom` is retired. A graph to resolve over is lifted into a gen-scope evaluated scope and walked by `resolve`; a labeled record kept as data for `forgetLabels`, `labeledTranspose` or `cyclicEdgesWhere` is written by hand, `{ nodes = [ … ]; labeledEdges = id: [ { label; target; } … ]; }`.";
  boundedBy = throw "gen-graph: `boundedBy` is retired. Boundary marks are read inside gen-scope's `resolve`: each node of the evaluation declares `marks`, a stated `bound` narrows further, and the result's `withheld` names every edge a mark withheld on the walk, at the scopes `resolve` reached. A graph-total `withheld` (an edge withheld at a node the walk never visited) is not answered.";
}
