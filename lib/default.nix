{ prelude }@args:
let
  modules = import ./modules.nix args;
in
{
  inherit (modules.declaredEdges)
    declaredEdgesFindings
    isDeclaredEdges
    isNodeRef
    mkDeclaredEdges
    mkNodeRef
    mkSpawnedNodeRef
    nodeRefFindings
    refName
    ;
  inherit (modules.edgeMaps)
    differenceEdges
    forgetLabels
    intersectEdges
    labeledTranspose
    materialize
    materializeParents
    selectEdges
    unionEdges
    ;
  inherit (modules.endpoints)
    mkEndpointProjection
    mkProjectionFindings
    ;
  inherit (modules.enumerate)
    leaves
    roots
    select
    ;
  inherit (modules.fixpoint)
    closureClass
    closureOf
    compose
    fixpoint
    seededFixpoint
    transitiveClosure
    transitiveReduction
    ;
  inherit (modules.global)
    coScc
    condensationClosure
    dependents
    dependentsFrontier
    dependentsOf
    directDependents
    directDependentsOf
    impactOf
    transpose
    ;
  inherit (modules.order)
    coneRank
    entryAfter
    entryAnywhere
    entryBefore
    entryBetween
    phaseOrder
    topoOrder
    topoOrderKahn
    ;
  inherit (modules.partition)
    condensation
    condensationOf
    cyclePaths
    cycles
    cyclicEdgesWhere
    fbNode
    fbWork
    lowlink
    ;
  inherit (modules.preorder)
    expandPreorder
    foldPreorder
    foldReach
    ;
  inherit (modules.registry)
    field
    fields
    fixtures
    fromRegistry
    fromScan
    labeledFixtures
    mkGraph
    ;
  inherit (modules.traverse)
    ancestorsOf
    canReach
    hoistEdges
    pathsBetween
    reachableFrom
    reachableVia
    reachableWhere
    selfReachable
    selfReachableVia
    ;
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
