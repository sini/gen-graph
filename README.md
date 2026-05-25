# gen-graph — accessor-based graph query combinators for Nix

Pure graph query combinators for Nix. Queries take accessor functions as arguments — not node maps. The graph structure is supplied by the caller; gen-graph only answers questions about it.

## Overview

gen-graph works with an **accessor record**: an attrset of functions that the caller provides to describe graph structure. Queries destructure only the accessors they need.

```nix
# Define accessors over your data
g = {
  edges    = id: myData.${id}.deps or [];      # id → [id]
  parent   = id: myData.${id}.parent or null;  # id → id | null
  nodes    = builtins.attrNames myData;         # [id]
  nodeData = id: myData.${id};                  # id → attrset
};

# Query
graph.reachableFrom g "web"      # → [ "api" "cache" "database" ]
graph.dependents    g "database" # → [ "api" "web" ]
graph.roots         g            # → [ "web" ]
graph.cycles        g            # → []
```

The four accessor fields:

| Field | Type | Used by |
|-------|------|---------|
| `edges` | `id → [id]` | traversal, global analysis, fixpoint |
| `parent` | `id → id \| null` | `ancestorsOf`, `materializeParents` |
| `nodes` | `[id]` | global analysis, enumeration, materialization |
| `nodeData` | `id → attrset` | `select` |

Functions that only need traversal destructure `{ edges, ... }`. Functions that need global analysis also take `nodes`. Functions that need parent walks take `parent`. No function requires all four.

## Quick Start

### As a flake input

```nix
{
  inputs.gen-graph.url = "github:sini/gen-graph";
  outputs = { gen-graph, nixpkgs, ... }:
    let
      lib   = nixpkgs.lib;
      graph = gen-graph { inherit lib; };
    in { /* use graph.reachableFrom, graph.roots, etc. */ };
}
```

### Without flakes

```nix
let
  lib   = (import <nixpkgs> {}).lib;
  graph = import ./path/to/gen-graph { inherit lib; };
in
graph.reachableFrom { edges = id: deps.${id} or []; } "start"
```

## Design Principles

- **Queries take accessor functions, not node maps.** The caller owns the data; gen-graph never stores it.
- **Traversal is lazy.** `reachableFrom`, `ancestorsOf`, and `pathsBetween` only visit nodes reachable from the start — they never enumerate `nodes`.
- **Global operations materialize internally.** `cycles`, `dependents`, `transpose`, `transitiveClosure`, and `transitiveReduction` call `materialize` once, then work on the resulting edge map.
- **Edge maps are always deduplicated.** `materialize` calls `lib.unique` on each target list. `unionEdges` calls `lib.unique` on merged lists.
- **Set operations use attrset membership.** Intersection and difference build a target attrset for O(1) per-edge lookups.

## API Reference

### Traversal (lazy)

These functions visit only the nodes they reach. They do not require `nodes`.

```
reachableFrom  : { edges, ... } → id → [id]
reachableWhere : { edges, ... } → id → (id → bool) → [id]
ancestorsOf    : { parent, ... } → id → [id]
pathsBetween   : { edges, ... } → id → id → [[id]]
```

**`reachableFrom g startId`** — all nodes transitively reachable from `startId` via `edges`, excluding `startId` itself. BFS with visited-set dedup.

```nix
graph.reachableFrom g "web"
# → [ "api" "cache" "database" ]
```

**`reachableWhere g startId pred`** — `reachableFrom` filtered by `pred id`.

```nix
graph.reachableWhere g "web" (id: lib.hasPrefix "cache" id)
# → [ "cache" ]
```

**`ancestorsOf g startId`** — walks `parent` links upward. Returns the chain from immediate parent to root. Cycle-safe: stops if a visited id is seen again.

```nix
graph.ancestorsOf g "grandchild"
# → [ "child1" "root" ]
```

**`pathsBetween g startId endId`** — all acyclic paths from `startId` to `endId`. Each path is a list of ids including both endpoints.

```nix
graph.pathsBetween g "a" "d"
# → [ [ "a" "b" "d" ] [ "a" "c" "d" ] ]   # diamond
```

### Global Analysis (materializes internally)

These functions enumerate all nodes. They require both `edges` and `nodes`.

```
cycles     : { edges, nodes, ... } → [id]
dependents : { edges, nodes, ... } → id → [id]
impactOf   : { edges, nodes, ... } → id → [id]   # alias for dependents
transpose  : { edges, nodes, ... } → { edges, nodes }
```

**`cycles g`** — nodes that appear in any cycle (self-reachable in the transitive closure). Returns a sorted list.

```nix
graph.cycles g   # → [] for a DAG, → [ "a" "b" "c" ] for a → b → c → a
```

**`dependents g targetId`** — all nodes that transitively reach `targetId` (reverse reachability). Sorted.

```nix
graph.dependents g "database"   # → [ "api" "web" ]
```

**`impactOf`** — alias for `dependents`. "What breaks if this node changes?"

**`transpose g`** — returns a new accessor record `{ edges, nodes }` with all edges reversed.

```nix
rev = graph.transpose g;
graph.reachableFrom rev "database"   # → nodes that depend on database
```

### Enumeration

These functions scan all nodes. They require `nodes`.

```
roots  : { edges, nodes, ... } → [id]
leaves : { edges, nodes, ... } → [id]
select : { nodes, nodeData, ... } → (attrset → bool) → [id]
```

**`roots g`** — nodes with no incoming edges (not a target of any edge). Sorted.

**`leaves g`** — nodes with no outgoing edges (`edges id == []`). Sorted.

**`select g pred`** — ids where `pred (nodeData id)` is true.

```nix
graph.select g (d: d.type == "backend")   # → [ "api" "worker" ]
```

### Materialization

```
materialize        : { edges, nodes, ... } → { id → [id] }
materializeParents : { parent, nodes, ... } → { id → id }
```

**`materialize g`** — builds an edge map `{ nodeId = [targetId ...]; }` for all nodes. Deduplicates each target list via `lib.unique`.

**`materializeParents g`** — builds `{ nodeId = parentId; }` for nodes where `parent id != null`.

### Fixpoint

```
fixpoint            : { seed, step, maxIter? } → edgeMap
compose             : edgeMap → edgeMap → edgeMap
transitiveClosure   : { edges, nodes, ... } → edgeMap
transitiveReduction : { edges, nodes, ... } → edgeMap
```

**`fixpoint { seed, step, maxIter? }`** — iterates `step` on `seed` until the result stabilizes (`next == current`). Throws if the step is non-monotonic (result shrinks) or exceeds `maxIter` (default 1000).

```nix
closure = graph.fixpoint {
  seed = graph.materialize g;
  step = current: graph.unionEdges current (graph.compose current (graph.materialize g));
};
```

**`compose e1 e2`** — relational composition of two edge maps. For each `a → b` in `e1` and `b → c` in `e2`, emits `a → c`.

**`transitiveClosure g`** — full transitive closure as an edge map. Materializes `g`, then iterates `compose` to fixpoint.

**`transitiveReduction g`** — minimal edge map preserving reachability. Removes edge `a → c` when `a → b → c` exists for some `b`.

### Edge Map Operations

These operate on materialized edge maps `{ id → [id] }`, not on accessor records.

```
unionEdges      : edgeMap → edgeMap → edgeMap
intersectEdges  : edgeMap → edgeMap → edgeMap
differenceEdges : edgeMap → edgeMap → edgeMap
selectEdges     : (id → id → bool) → edgeMap → edgeMap
```

**`unionEdges a b`** — merged edge map; target lists are deduplicated.

**`intersectEdges a b`** — only edges present in both maps. Empty target lists are dropped.

**`differenceEdges a b`** — edges in `a` not in `b`. Empty target lists are dropped.

### Mock Utility

`graph.mock` provides test helpers for constructing accessor records from declarative edge lists.

```
mkGraph     : { edges?, parents?, nodeData? } → accessorRecord
fromNodeMap : { id → { imports?, parent?, ... } } → accessorRecord
fixtures    : { diamond, chain, cyclic, tree, serviceGraph, disconnected }
```

**`mkGraph`** — takes edge lists and returns a valid accessor record with all four fields populated.

```nix
g = graph.mock.mkGraph {
  edges = [
    { from = "a"; to = "b"; }
    { from = "b"; to = "c"; }
  ];
  nodeData = {
    a = { label = "start"; };
    c = { label = "end"; };
  };
};

graph.reachableFrom g "a"             # → [ "b" "c" ]
graph.select g (d: d ? label)         # → [ "a" "c" ]
```

**`fixtures`** — pre-built accessor records for common graph shapes:

| Name | Shape |
|------|-------|
| `diamond` | `a → b,c → d` |
| `chain` | `a → b → c → d` |
| `cyclic` | `a → b → c → a` |
| `tree` | parent chain: grandchild → child1 → root |
| `serviceGraph` | web/api/worker/db/cache/queue with nodeData |
| `disconnected` | a → b plus isolated `island` node |

## Usage Example

```nix
{ nixpkgs, gen-graph }:
let
  lib   = nixpkgs.lib;
  graph = gen-graph { inherit lib; };

  # Your data
  services = {
    web    = { deps = [ "api" ];         type = "frontend";  };
    api    = { deps = [ "db" "cache" ];  type = "backend";   };
    worker = { deps = [ "db" "queue" ];  type = "backend";   };
    db     = { deps = [];                type = "datastore";  };
    cache  = { deps = [];                type = "datastore";  };
    queue  = { deps = [];                type = "datastore";  };
  };

  # Accessor record
  g = {
    edges    = id: services.${id}.deps or [];
    parent   = _: null;
    nodes    = builtins.attrNames services;
    nodeData = id: services.${id};
  };
in {
  entryPoints  = graph.roots g;                               # [ "web" "worker" ]
  datastores   = graph.leaves g;                              # [ "cache" "db" "queue" ]
  webDeps      = graph.reachableFrom g "web";                 # [ "api" "cache" "db" ]
  dbImpact     = graph.dependents g "db";                     # [ "api" "web" "worker" ]
  backendNodes = graph.select g (d: d.type == "backend");     # [ "api" "worker" ]
  hasCycles    = graph.cycles g != [];                        # false
}
```

## Performance

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| `reachableFrom` | O(visited nodes + edges) | BFS; stops at visited |
| `reachableWhere` | O(visited nodes + edges) | same BFS, filter applied after |
| `ancestorsOf` | O(depth) | single-path walk |
| `pathsBetween` | O(paths × depth) | exponential in path count; use on small graphs |
| `materialize` | O(nodes × avg degree) | one-time scan |
| `transitiveClosure` | O(nodes² × iterations) | fixpoint over materialized map |
| `transitiveReduction` | O(nodes²) | needs full closure |
| `cycles` / `dependents` | O(nodes²) | both use transitive closure |
| `roots` / `leaves` | O(nodes × avg degree) | single scan of all edges |
| `select` | O(nodes) | one pass over node list |
| `unionEdges` / `intersectEdges` / `differenceEdges` | O(edges) | attrset membership O(1) per edge |

Lazy traversal (`reachableFrom`, `ancestorsOf`, `pathsBetween`) visits only what is reachable. Global operations (`cycles`, `dependents`, `transpose`, `transitiveClosure`, `transitiveReduction`) materialize the full graph internally.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries — accessor-based combinators, traversal, fixpoint |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries — kinds, instances, collections, refs |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs — construction, evaluation, resolution |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra — neededBy, pipe.gather, policy.when |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types — traits, classification, dispatch |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding — inject external args into NixOS modules |

## Testing

```bash
nix flake check --override-input gen-graph . ./templates/ci
```

## References

The algorithms and design principles draw from:

- **Mokhov (2017)** — *Algebraic Graphs with Class*. Edge map set operations (union, intersect, difference) and transitive reduction follow the algebraic graph framework.
- **Arntzenius & Krishnaswami (2016)** — *Datafun: A Functional Datalog*. Monotone fixpoint iteration with convergence guarantees. The `fixpoint` operator enforces monotonicity (edge count must not shrink).
- **Neron et al. (2015)** — *A Theory of Name Resolution*. Parent-chain traversal (`ancestorsOf`) follows scope graph P-edge resolution. Silent cycle termination chosen over throwing for composability.
- **Kahn (1974)** — *The Semantics of a Simple Language for Parallel Programming*. Demand-driven evaluation model — traversal only forces nodes it visits, matching Nix's lazy semantics.
- **Radul (2009)** — *The Art of the Propagator*. Influence on the accessor-function pattern — queries compose via function arguments rather than shared mutable state.

## License

MIT
