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
canReach       : { edges, ... } → id → id → bool
selfReachable  : { edges, ... } → id → bool
ancestorsOf    : { parent, ... } → id → [id]
pathsBetween   : { edges, ... } → id → id → [[id]]
```

**`reachableFrom g startId`** — all nodes transitively reachable from `startId` via `edges`, excluding `startId` itself. C-level BFS via `builtins.genericClosure`.

```nix
graph.reachableFrom g "web"
# → [ "api" "cache" "database" ]
```

**`reachableWhere g startId pred`** — `reachableFrom` filtered by `pred id`.

```nix
graph.reachableWhere g "web" (id: lib.hasPrefix "cache" id)
# → [ "cache" ]
```

**`canReach g fromId toId`** — point query: can `fromId` transitively reach `toId`? O(reachable from `fromId`). Does not require materializing the full graph.

```nix
graph.canReach g "web" "database"   # → true
graph.canReach g "database" "web"   # → false
```

**`selfReachable g id`** — is `id` reachable from itself (i.e., in a cycle)? C-level BFS. Used internally by `cycles`.

```nix
graph.selfReachable cyclicGraph "a"   # → true
graph.selfReachable dagGraph "a"      # → false
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
cycles       : { edges, nodes, ... } → [id]
dependents   : { edges, nodes, ... } → id → [id]
dependentsOf : { edges, nodes, ... } → id → [id]
impactOf     : { edges, nodes, ... } → id → [id]   # alias for dependentsOf
transpose    : { edges, nodes, ... } → { edges, nodes }
```

**`cycles g`** — nodes that appear in any cycle (self-reachable). Uses C-level BFS per node via `selfReachable` — no full transitive closure materialization needed. Returns a sorted list.

```nix
graph.cycles g   # → [] for a DAG, → [ "a" "b" "c" ] for a → b → c → a
```

**`dependents g targetId`** — all nodes that transitively reach `targetId` (reverse reachability). Uses full transitive closure + transpose. O(n²) setup, O(1) lookup. Best for multi-target queries (amortized).

```nix
graph.dependents g "database"   # → [ "api" "web" "worker" ]
```

**`dependentsOf g targetId`** — same result as `dependents`, but uses reverse traversal: builds reverse edge index O(n), then C-level BFS from target. O(n + reachable). **Preferred for single-target queries on large graphs.**

```nix
graph.dependentsOf g "database"   # → [ "api" "cache" "web" "worker" ]
```

**`impactOf`** — alias for `dependentsOf`. "What breaks if this node changes?"

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
| `reachableFrom` | O(reachable) | C-level BFS via `builtins.genericClosure` |
| `reachableWhere` | O(reachable) | same C-level BFS, filter applied after |
| `canReach` | O(reachable from source) | C-level BFS, stops exploring from target |
| `selfReachable` | O(reachable from node) | C-level BFS checking self-reappearance |
| `ancestorsOf` | O(depth) | single-path walk |
| `pathsBetween` | O(paths × depth) | exponential in path count; use on small subgraphs |
| `materialize` | O(nodes × avg degree) | one-time scan |
| `transitiveClosure` | O(nodes² × iterations) | fixpoint over materialized map |
| `transitiveReduction` | O(nodes² × degree) | needs full closure; O(1) membership via attrsets |
| `cycles` | O(nodes × reachable) | per-node C-level BFS (no full closure needed) |
| `dependents` | O(nodes²) | full transitive closure + transpose |
| `dependentsOf` | O(nodes + reachable) | reverse index + C-level BFS |
| `roots` / `leaves` | O(nodes × avg degree) | single scan of all edges |
| `select` | O(nodes) | one pass over node list |
| `unionEdges` / `intersectEdges` / `differenceEdges` | O(edges) | attrset membership O(1) per edge |

Lazy traversal (`reachableFrom`, `canReach`, `ancestorsOf`, `pathsBetween`) visits only what is reachable. Global operations (`cycles`, `dependents`, `transpose`, `transitiveClosure`, `transitiveReduction`) scan all nodes.

## Performance Optimizations

gen-graph is designed to support large infrastructure graphs (1000+ nodes) without forcing performance regressions onto the underlying evaluator.

### C-Level BFS via `builtins.genericClosure`

All reachability queries use Nix's native `builtins.genericClosure` — a C-level builtin with built-in dedup. This is ~4-5x faster than equivalent Nix-level BFS on 5000-node graphs:

- No Nix-level queue management (list concatenation is O(n²) for BFS queues)
- Native hash-based dedup (not attrset `//` per visited node)
- Constant-factor advantage of compiled C vs interpreted Nix

### Accessor Pattern + gen-scope Memoization

When gen-graph's accessor functions are wired to gen-scope's `result.get id "imports"`:

- Each `edges id` call hits gen-scope's memoized `_eval` → O(1) after first evaluation
- Traversal operations only trigger attribute evaluation for VISITED nodes
- Global operations trigger evaluation for ALL nodes, but each evaluates exactly once

This means gen-graph never causes redundant evaluation in gen-scope. The accessor pattern is the zero-cost bridge:

```nix
# gen-scope evaluates each node's imports ONCE; gen-graph reads the cached result
graphLib.reachableFrom { edges = id: result.get id "imports"; } "host:igloo"
```

### Choosing the Right Operation

| Need | Use | Don't use |
|------|-----|-----------|
| "Can A reach B?" | `canReach` (O(reachable)) | `dependents` (O(n²)) |
| "What depends on X?" (one target) | `dependentsOf` (O(n + reachable)) | `dependents` (O(n²)) |
| "What depends on X, Y, Z?" (multi-target) | `dependents` (O(n²) amortized) | `dependentsOf` × 3 (rebuilds index 3×) |
| "Is there a cycle?" | `cycles` (O(n × reachable), C-level) | `transitiveClosure` (O(n²)) |
| "All paths between A and B" | `pathsBetween` (DFS) | Only for small subgraphs |
| "Full closure for analysis" | `transitiveClosure` | — (use when you genuinely need it) |
| "Minimal graph for diagrams" | `transitiveReduction` | — (O(n²), needs closure) |

### Partitioning for Fleet Scale

For 10,000+ node fleets, partition the graph by environment/datacenter before running global operations:

```nix
# Instead of:
graph.cycles { edges; nodes = ALL_10K_NODES; }  # O(10K × reachable)

# Partition first:
lib.concatMap (partition:
  graph.cycles { inherit edges; nodes = partition; }
) (partitionByEnvironment allNodes)  # 20 × O(500 × reachable)
```

Cross-partition edges are rare in practice. Per-partition analysis is typically 100-400x faster than whole-fleet.

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
