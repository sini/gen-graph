# gen-graph — accessor-based graph query combinators for Nix

[![CI](https://github.com/sini/gen-graph/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-graph/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Pure graph query combinators for Nix. Queries take accessor functions as arguments — not node maps. The graph structure is supplied by the caller; gen-graph only answers questions about it.

## Table of Contents

- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Quick Start](#quick-start)
- [Design Principles](#design-principles)
- [API Reference](#api-reference)
- [Usage Example](#usage-example)
- [Performance](#performance)
- [Performance Optimizations](#performance-optimizations)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

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

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject args into NixOS modules) |
| [gen-derive](https://github.com/sini/gen-derive) | Rule dispatch (stratified phases, fixpoint, conflict resolution) |

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
cycles             : { edges, nodes, ... } → [id]
dependents         : { edges, nodes, ... } → id → [id]
dependentsOf       : { edges, nodes, ... } → id → [id]
dependentsFrontier : { edges, nodes, ... } → id → (id → bool) → [id]
impactOf           : { edges, nodes, ... } → id → [id]   # alias for dependentsOf
transpose          : { edges, nodes, ... } → { edges, nodes }
coScc              : { edges, ... } → id → id → bool
condensation       : { edges, nodes, ... } → { reps, bottomUp, members, sccs, sccOf, condEdges }
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

**`dependentsFrontier g targetId prune`** — `dependentsOf` with an early cutoff. Walks the reverse-reachability cone level by level, but descends into a node's own dependents only when `prune node` is `true`. A pruned node is still **included** in the result (it was reached) but is not expanded, so nothing beyond it is walked. Cycle-safe via a visited set. Reduces exactly to `dependentsOf` when `prune = _: true`.

```nix
# Everything that depends on db, but stop walking past api:
graph.dependentsFrontier g "db" (id: id != "api")
# → [ "api" "worker" ]   # api included, but web (which only reaches db via api) is cut
```

**`impactOf`** — alias for `dependentsOf`. "What breaks if this node changes?"

**`transpose g`** — returns a new accessor record `{ edges, nodes }` with all edges reversed.

```nix
rev = graph.transpose g;
graph.reachableFrom rev "database"   # → nodes that depend on database
```

**`coScc g u v`** — are `u` and `v` in the same strongly connected component? `canReach`-backed point query (no full closure): true iff `u == v`, or each reaches the other.

```nix
graph.coScc cyclicGraph "a" "c"   # → true  (a → b → c → a)
graph.coScc dagGraph     "a" "b"  # → false
```

**`condensation g`** — collapses each SCC to a super-node and returns the condensation (quotient) graph. Closure-based O(n²) — not Tarjan's linear single-DFS, whose mutable stack is out of reach in pure Nix. Returns a record:

| Field | Type | Meaning |
|-------|------|---------|
| `reps` | `[tag]` | SCC tags in bottom-up order (`== bottomUp`) |
| `bottomUp` | `[tag]` | SCCs in reverse-topological order: each appears after every SCC it points to |
| `members` | `tag → [id]` | the member ids of one SCC, sorted |
| `sccs` | `[[id]]` | member lists, in `bottomUp` order |
| `sccOf` | `id → tag` | the SCC tag (smallest member id) of a node |
| `condEdges` | `tag → [tag]` | the SCCs that this SCC points to |

```nix
c = graph.condensation g;
c.sccs              # → [ [ "d" ] [ "c" ] [ "b" ] [ "a" ] ]  for chain a → b → c → d
c.sccOf "a"         # → "a"
c.condEdges (c.sccOf "a")   # → SCCs that a's component depends on
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
seededFixpoint      : { seed, frontier, step, maxIter? } → edgeMap
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

**`seededFixpoint { seed, frontier, step, maxIter? }`** — semi-naive variant of `fixpoint`. Here `step` takes two arguments, `step frontier accumulator`, and is shown **only the current delta frontier** rather than the whole accumulator — so each iteration does work proportional to what changed, not to the full result. Newly produced facts join the accumulator and become the next frontier; it converges when the frontier empties. No monotonicity guard is needed since union-accumulation never shrinks. Throws past `maxIter` (default 1000).

```nix
# Semi-naive transitive closure: dR = dF ∘ R each round.
mat = graph.materialize g;
closure = graph.seededFixpoint {
  seed     = mat;
  frontier = mat;
  step     = dF: _acc: graph.compose dF mat;
};
```

**`compose e1 e2`** — relational composition of two edge maps. For each `a → b` in `e1` and `b → c` in `e2`, emits `a → c`.

**`transitiveClosure g`** — full transitive closure as an edge map. Materializes `g`, then iterates `compose` to fixpoint.

**`transitiveReduction g`** — minimal edge map preserving reachability. Removes edge `a → c` when `a → b → c` exists for some `b`. Standard DAG transitive reduction (gen-graph's own implementation); assumes a DAG — the reduction is unique only on acyclic graphs.

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

### Construction

Top-level helpers for building accessor records, exported flat (no `mock` namespace).

```
mkGraph      : { edges?, parents?, nodeData? } → accessorRecord
fromRegistry : { registry, edges, parent? } → accessorRecord
field        : name → id → entry → [id]
fields       : [name] → id → entry → [id]
fixtures     : { diamond, chain, cyclic, tree, serviceGraph, disconnected }
```

**`mkGraph`** — takes declarative `{ from; to; }` edge lists and returns a valid accessor record with all four fields populated.

```nix
g = graph.mkGraph {
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

**`fromRegistry`** — wraps an arbitrary registry attrset. `edges`/`parent` are `id → entry → …` projections applied per node; `field`/`fields` build common projections.

```nix
g = graph.fromRegistry {
  registry = myNodes;
  edges = graph.field "deps";   # each entry's `deps` list
};
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
| `dependentsFrontier` | O(nodes + reachable) | reverse index + level-by-level BFS, pruned early |
| `coScc` | O(reachable from u, v) | two `canReach` probes, no full closure |
| `condensation` | O(nodes²) | two transitive closures (graph + quotient) |
| `seededFixpoint` | O(work per delta) | semi-naive: each iteration touches only the frontier |
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
genGraph.reachableFrom { edges = id: result.get id "imports"; } "host:igloo"
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

## Testing

```bash
nix flake check --override-input gen-graph . ./ci
```

## Theoretical Foundations

The algorithms and design principles draw from:

- **Mokhov (2017)** — *Algebraic Graphs with Class*. *Informed by.* Algebraic graph construction primitives (overlay, connect, vertex, empty) and the compositional approach to graph representation inform gen-graph's edge map operations and structural combinators. Edge map set operations (`unionEdges`, `intersectEdges`, `differenceEdges`) are gen-graph's own contribution built on this algebraic foundation. Mokhov 2017 §4.5 supplies only the equivalence-class *notion* of reduction; `transitiveReduction` is a standard DAG transitive-reduction algorithm (gen-graph's own implementation) and assumes a DAG, since reduction is not unique under cycles. Transpose follows Mokhov 2017 §4.3 directly.
- **Arntzenius & Krishnaswami (2016)** — *Datafun: A Functional Datalog*. *Implements.* Monotone fixpoint iteration with convergence guarantees. The `fixpoint` operator enforces monotonicity (edge count must not shrink between iterations), matching Datafun's requirement that fixpoint computations operate over monotone functions on semilattices. Reverse reachability in `dependents`/`dependentsOf` follows the Datafun reverse-query pattern.
- **Neron et al. (2015)** — *A Theory of Name Resolution*. *Implements.* Parent-chain traversal (`ancestorsOf`) follows scope graph P-edge resolution: walking the `parent` partial function upward through scopes corresponds to following P-edges in the resolution calculus (Neron 2015 §2.3). Silent cycle termination chosen over throwing for composability, matching the well-foundedness requirement on the parent relation.
- **Kahn (1974)** — *The Semantics of a Simple Language for Parallel Programming*. *Informed by.* Continuous functions over streams with deterministic dataflow semantics. gen-graph's lazy accessor pattern — traversal only forces nodes it visits — aligns conceptually with Kahn's model where computing stations produce output incrementally as input arrives, and monotonicity ensures that receiving more input can only provoke more output (Kahn 1974 §2.2.4).
