# gen-graph — accessor-based graph query combinators for Nix

[![CI](https://github.com/sini/gen-graph/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-graph/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Pure graph query combinators for Nix. Queries take accessor functions as arguments — not node maps. The graph structure is supplied by the caller; gen-graph only answers questions about it.

gen-graph is **nixpkgs-lib-free** (Class B): it depends only on [gen-prelude](https://github.com/sini/gen-prelude), the pure utility base — no `nixpkgs.lib`, no module system.

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
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-types](https://github.com/sini/gen-types) | Clean-room MIT structural type checker (leaf/poly checkers; `verify: v → null\|err`) |
| [gen-merge](https://github.com/sini/gen-merge) | Byte-mode module merge engine (`evalModuleTree`, byte-identical to nixpkgs `lib.evalModules` over the priority subset) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs); re-hosted on gen-merge |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system (traits, classification, dispatch); re-hosted on gen-merge |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | **This lib** — Accessor-based graph query combinators (traversal, condensation, topoOrder/phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-rebuild](https://github.com/sini/gen-rebuild) | Pure-Nix incremental rebuilder (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |
| [gen-flake](https://github.com/sini/gen-flake) | The nixpkgs boundary — compose purely, inject resolved values, build NixOS systems (value-injection) |

## Quick Start

### As a flake input

```nix
{
  inputs.gen-graph.url = "github:sini/gen-graph";
  # gen-graph pulls in gen-prelude transitively — no nixpkgs input required.
  outputs = { gen-graph, ... }:
    let
      graph = gen-graph.lib;
    in { /* use graph.reachableFrom, graph.roots, graph.phaseOrder, etc. */ };
}
```

### Without flakes

The standalone entry derives its only dependency (gen-prelude) from the pinned
`flake.lock`, so it needs no `<nixpkgs>` and takes no arguments:

```nix
let
  graph = import ./path/to/gen-graph { };   # prelude auto-derived from flake.lock
in
graph.reachableFrom { edges = id: deps.${id} or []; } "start"
```

Pass `prelude` explicitly to override it: `import ./path/to/gen-graph { prelude = gen-prelude.lib; }`.

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

And their **amortized dual**, for a caller spending many traversals over one accessor. `hoistEdges`
is **eager in the node set and lazy in each node's edges**: it builds a `Θ(n)` spine over `nodes` up
front, and a node's `edges` call happens on first lookup, so a traversal still never reads the edges
of a node it does not visit:

```
hoistEdges       : { edges, nodes, ... } → (id → succ)
reachableVia     : (id → succ) → id → [id]
selfReachableVia : (id → succ) → id → bool
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

**`canReach g fromId toId`** — point query: can `fromId` transitively reach `toId`? The traversal **stops expanding at the target**, so it costs `Θ(Σ_{u ∈ visited} (1 + outdeg u))` over `reach fromId` **less the nodes `toId` dominates** — O(reachable) only where out-degree is **bounded**, Θ(n²) on a complete DAG. ★ **The win is scoped to targets that dominate a sub-closure**: on a chain walked from the tail a one-hop query is Θ(1) where the full walk was Θ(n), while on a complete digraph every node sits one hop from the source and the query stays Θ(n²) — `ci/bench/canreach-exit.nix` reads both regimes as a pair. The target still **enters** the closure whenever it is reachable, so the answer is unchanged; `builtins.any` short-circuits its scan of the finished list, not the traversal that built it.

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

**`hoistEdges g`** / **`reachableVia succ startId`** / **`selfReachableVia succ id`** — the same two traversals with the per-visit work lifted out. The operators above re-read `edges` at every visit and wrap each successor into `genericClosure`'s item shape there, so a visit costs `O(1 + outdeg)`; `hoistEdges` does that wrapping **once** over `nodes` and returns the successor function, and the two `*Via` operators read it. Semantics are identical — same reachable set, same order, same exclusion of the start — and a target outside `nodes` still expands through the accessor, so hoisting cannot truncate a walk.

**This is amortization, so it is a trade and not an improvement.** `k` traversals over one accessor go from `Θ(k · Σ (1 + outdeg))` attrsets to `Θ(n + E) + Θ(k · |reach|)`: a whole class removed where `k` is large, and a straight loss where `k` is 1, because the wrap's `Θ(n)` spine is built over every node while one traversal reads only the ones it reaches. Reach for it only when the same accessor is walked many times.

```nix
let succ = graph.hoistEdges g;                     # read the accessor once
in map (graph.reachableVia succ) g.nodes           # …spend it n times
```

Inside this library `cycles` and `fbNode` bind it and `dependentsOf` and `fbWork` deliberately do not — see their cost rows for the measurement each decision rests on.

**`pathsBetween g startId endId`** — all acyclic paths from `startId` to `endId`. Each path is a list of ids including both endpoints.

```nix
graph.pathsBetween g "a" "d"
# → [ [ "a" "b" "d" ] [ "a" "c" "d" ] ]   # diamond
```

### Pre-order Traversal (ordered, payload-carrying)

`reachableFrom` is C-level but BFS, single-keyed and payload-blind — it returns a *set*, in
no guaranteed order, with no way to expose the traversed edge or carry a projection. These
combinators are the missing **DFS pre-order**, **payload-carrying**, **edge-exposing** dual:
a frame is folded before its children, siblings in list order, each frame visited once (first
occurrence wins) via a threaded visited attrset. They visit only what they reach, and a
frame's successors may be **demand-generated** (forced only when the frame is reached).

```
foldPreorder   : { roots; key; expand; acc; visited? }                              → { acc; visited }
expandPreorder : { roots; key; edges; resolve?; emit?; seen0?; nodes0? }            → { nodes; seen }
foldReach      : { roots; edges; target; project; itemKey; visited0?; seen0?; nodes0? } → { nodes; seen; visited }
```

**`foldPreorder`** — the primitive. A pre-order DFS fold with a caller-owned accumulator and a
first-occurrence visited set. `key frame` is the cycle-guard/dedup key (a `null` key is never
guarded); `expand acc frame → { acc; children? }` folds this frame in and yields its child
frames; `visited` seeds the guard set (a pre-seeded key prunes that frame's subtree without
forcing it). `expandPreorder` and `foldReach` are thin specializations of it.

```nix
# classify a nested include tree into two buckets, cycle-guarded by .key
graph.foldPreorder {
  roots  = [ rootNode ];
  key    = v: v.key or null;
  acc    = { recs = [ ]; bares = [ ]; };
  expand = acc: v: {
    acc = { recs = acc.recs ++ policyIncludes v; bares = acc.bares ++ bareIncludes v; };
    children = subRecords v;
  };
}
```

**`expandPreorder`** — payload-carrying DFS-preorder closure. Folds `emit frame (resolve frame)`
in first-occurrence pre-order into an ordered witness list. `resolve` is the (possibly
parametric) node force; `edges` reads the **resolved** payload's successors, so a node's
children can be demand-generated (they exist only after `resolve` invokes it). One key set —
`key frame` both cycle-guards and dedups. `seen0`/`nodes0` seed the guard set and the witness
list.

```nix
graph.expandPreorder {
  roots   = aspectList;
  key     = a: a.key;
  resolve = a: if a.__isWrappedFn or false then a ctx else a;   # parametric invoke
  edges   = concrete: concrete.includes or [ ];                  # demand-generated
  emit    = a: concrete: { inherit (a) key; content = concrete; };
  seen0   = droppedKeys;
}
# → { nodes = [ … witness, pre-order … ]; seen = { … }; }
```

**`foldReach`** — labeled, suppression-aware, transitive reach fold. Folds over labeled
**edges**, each carrying a `target` vertex and a projection label; `project edge → [item]` is
the per-edge content projection with the whole edge **exposed** (so it can slice the target's
content by the edge's label — one edge → many items). Negative-edge **suppression** is expressed
by the `edges` accessor itself (return a vertex's edges minus the suppressed ones), so the fold
is suppression-aware by construction. Two key sets, because one vertex projects many items:
`target edge` cycle-guards the vertex DFS (`visited0`), `itemKey item` first-occurrence-dedups
the witness across vertices (`seen0`; a `null` item key is kept, never deduped).

```nix
graph.foldReach {
  roots    = edgesAt startId;                 # edgesAt bakes in suppression
  edges    = edgesAt;
  target   = e: e.target;
  project  = e: builtins.filter (classFilter e) (contentAt e.target);   # per-edge label projection
  itemKey  = n: n.key;
  visited0 = { ${startId} = true; };
  seen0    = structuralKeys;                   # structural component already emitted
  nodes0   = structuralNodes;
}
# → { nodes = [ … ordered witness … ]; seen = { … }; visited = { … }; }
```

### Global Analysis (materializes internally)

These functions enumerate all nodes. They require both `edges` and `nodes`.

```
cycles             : { edges, nodes, ... } → [id]
cyclePaths         : { edges, nodes, ... } → [[id]]
dependents         : { edges, nodes, ... } → id → [id]
dependentsOf       : { edges, nodes, ... } → id → [id]
dependentsFrontier : { edges, nodes, ... } → id → (id → bool) → [id]
impactOf           : { edges, nodes, ... } → id → [id]   # alias for dependentsOf
transpose          : { edges, nodes, ... } → { edges, nodes }
coScc              : { edges, ... } → id → id → bool
condensation       : { edges, nodes, ... } → { reps, bottomUp, members, sccs, sccOf, condEdges, depth }
fbNode             : { edges, nodes, ... } → <the same record>   # partition arm, the door's default
fbWork             : { edges, nodes, ... } → <the same record>   # partition arm, by name
condensationClosure: { edges, nodes, ... } → <the same record>   # partition arm, by name
condensationOf     : { edges, nodes, ... } → tagOf → <the same record>   # the finisher every arm calls
directDependents   : { edges, nodes, ... } → { id → [id] }
directDependentsOf : { edges, nodes, ... } → id → [id]
```

`coneRank` is an ordering surface and is documented under **Ordering** below.

**`cycles g`** — nodes that appear in any cycle (self-reachable). Uses C-level BFS per node via `selfReachableVia` — one closure per node, no full transitive closure materialization needed. Because it spends n closures on one accessor it reads that accessor once (`hoistEdges`) rather than at every visit of every closure. Returns a sorted list.

```nix
graph.cycles g   # → [] for a DAG, → [ "a" "b" "c" ] for a → b → c → a
```

**`cyclePaths g`** — one representative simple cycle per cyclic component, as an **ordered** node list rotated to begin at the component's smallest key. `[]` for a DAG. Where `cycles` answers *which nodes lie on a cycle* (a key-sorted membership set), `cyclePaths` answers *what the loop is*: every consecutive pair in a returned list is a real edge, so a caller may join it with `->` and state something true. Reach for it whenever the cycle is going to be **shown to a human**.

One per component, not all: the SCC is the canonical object, the cycle through it is existential. Enumerating every simple cycle is Johnson 1975 and is deliberately not provided.

Cost is asymmetric by design. `cycles` short-circuits a DAG before any path work, so the acyclic case — the ordinary one — pays the self-reachability pass and nothing more. That pass *is* `cycles`, so it inherits `cycles`' shape dependence: O(n × reachable) where out-degree is bounded, and Θ(n²) on a complete DAG — the out-degree factor is charged once by the accessor hoist rather than at every visit (see Performance). The partition arm and `pathsBetween` run only once the graph is known cyclic, i.e. only on the branch a caller refuses on.

```nix
# b → d → c → b, keys sorting b < c < d
graph.cycles g       # → [ "b" "c" "d" ]   membership, key-sorted
graph.cyclePaths g   # → [ [ "b" "d" "c" ] ]   the traversal — b→d, d→c, c→b
```

**`dependents g targetId`** — all nodes that transitively reach `targetId` (reverse reachability). Uses full transitive closure + transpose — closure-class cost (super-quadratic, see Performance), O(1) lookup thereafter. Best for multi-target queries (amortized).

```nix
graph.dependents g "database"   # → [ "api" "web" "worker" ]
```

**`dependentsOf g targetId`** — same result as `dependents`, but uses reverse traversal: builds the reverse edge index over every edge (`Θ(n + E)`), then runs the same C-level BFS from the target over that index, costing `Θ(Σ_{u ∈ reach⁻ target} (1 + indeg u))` — the operator re-reads the index at every visit, and in the reversed graph a node's out-degree is its forward **in**-degree. O(reachable) only where in-degree is bounded; Θ(n²) on a complete DAG. **Preferred for single-target queries on large graphs.**

```nix
graph.dependentsOf g "database"   # → [ "api" "cache" "web" "worker" ]
```

**`dependentsFrontier g targetId prune`** — `dependentsOf` with an early cutoff. Walks the reverse-reachability cone level by level, but descends into a node's own dependents only when `prune node` is `true`. A pruned node is still **included** in the result (it was reached) but is not expanded, so nothing beyond it is walked. Cycle-safe: the traversal is the same C-level `genericClosure` `dependentsOf` uses, with `prune` consulted inside the operator, so the done set is the guard. Reduces exactly to `dependentsOf` when `prune = _: true`.

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

**`coScc g u v`** — are `u` and `v` in the same strongly connected component? `canReach`-backed point query: true iff `u == v`, or each reaches the other. **Each probe stops expanding at its own target**, so it materializes its start's closure less the sub-closure that target dominates — and where the target dominates nothing, the whole of it. What is avoided is the whole-graph transitive closure and the dominated remainder, not the rest of the per-probe one.

★ **Export-only, and so is the probe underneath it.** Nothing in `lib/` calls `coScc` — the `condensationClosure` arm decides co-SCC from its own materialized closure, not through this name — and `coScc` is in turn the only caller of `canReach` in `lib/`. **So the two-probe cost is yours to price**, against your own call pattern: the library states the shape (below) but owes no figure on a surface it never calls, and no bench arm measures one. Probing many pairs re-materializes both closures every pair; hold `transitiveClosure` or a `condensation` record once instead.

```nix
graph.coScc cyclicGraph "a" "c"   # → true  (a → b → c → a)
graph.coScc dagGraph     "a" "b"  # → false
```

**`condensation g`** — collapses each SCC to a super-node and returns the condensation (quotient) graph. This is the **one published front door for SCC partitioning**; it carries the default, and the arms behind it are published under their own names (see *The partition routing contract* below). Not Tarjan's linear single-DFS, whose mutable stack is out of reach in pure Nix. Returns a record:

| Field | Type | Meaning |
|-------|------|---------|
| `reps` | `[tag]` | SCC tags in bottom-up order (`== bottomUp`) |
| `bottomUp` | `[tag]` | SCCs in reverse-topological order: each appears after every SCC it points to |
| `members` | `{ tag → [id] }` | the member ids of each SCC, sorted |
| `sccs` | `[[id]]` | member lists, in `bottomUp` order |
| `sccOf` | `{ id → tag }` | the SCC tag (smallest member id) of each node |
| `condEdges` | `{ tag → [tag] }` | the SCCs that each SCC points to |
| `depth` | `int` | the **longest path** over the condensation DAG, in edges |

```nix
c = graph.condensation g;
c.sccs              # → [ [ "d" ] [ "c" ] [ "b" ] [ "a" ] ]  for chain a → b → c → d
c.sccOf."a"         # → "a"
c.condEdges.${c.sccOf."a"}   # → SCCs that a's component depends on
c.depth             # → 3
```

**The three lookups are MAPS, not functions**, and that is a contract rather than a style: the door is read across library boundaries, where a foreign evaluation receives only strings, lists, integers and attrsets of those. A function's identity is minted by the build that made it and does not survive the crossing — `builtins.toJSON` of a record carrying one aborts, uncatchably. A caller that wants a lookup builds one from the map on its own side (`id: c.sccOf.${id} or id` restores the older spelling exactly). ★ The maps are defined on `nodes` and on the tags respectively, so an id that is not in `nodes` is a missing attribute rather than a value: the older function form answered `sccOf "nope"` with `"nope"`, and the map does not.

**`depth` is the longest path and nothing else.** Three different quantities travel under the word — the longest path over the condensation DAG, the closure *cardinality* of a class, and the summed per-node reach Σ|reach(v)| over atoms — and they separate by the full width of the graph. On a hub depending on 19 leaves the cardinality is 19 and the longest path is 1. Only the longest path is published, because the partition **determines** every one of the others: a consumer computes whichever its own cost model is fitted over, from `{ sccs, sccOf, condEdges }`, and names its own domain where it derives it. Publishing one of them here would decide that for every consumer; publishing all of them would be this library doing the consumer's work.

#### The partition routing contract

**Which arm answers by default.** `condensation` is the front door and delegates to **`fbNode`**, the per-node forward–backward arm. The delegation is an identity, not a wrapper, so the door cannot drift from the arm it names. Every consumer *inside* this library binds an arm by name rather than the door — `topoOrderKahn`'s cycle report, `cyclePaths` and `cyclicEdgesWhere` all bind `fbNode` — because the door's own result is finished with an ordering pass, and an ordering surface reading the door would be ordering through a surface that orders through it.

**How the other arms are reached.** By name: `fbWork` and `condensationClosure`. There is no mode flag on the door, and that is deliberate: a routing decision is a property of the program, computed once, and a caller-selected mode is a second place the default lives — one a caller can use to select the arm that cannot express their graph. A named arm has no default to disagree with.

**What the result carries.** The partition itself (`sccs`, `sccOf`, `condEdges`, plus `reps`/`bottomUp`/`members`) and one measure, `depth`. All plain data. Every arm returns the identical record on every graph where all three answer, and that is a property of the CONSTRUCTION rather than of the cells that check it: each arm computes a tag map and nothing else, then calls the one exported finisher, `condensationOf`. An arm that finished its own record would agree with its siblings only for as long as someone kept three copies in step. `condensationOf` takes an accessor and a tag map; its precondition is that the tag map is an SCC partition's, total on `nodes`, since any other map can induce a cyclic quotient — which the ordering pass refuses by name rather than answering.

**When each arm wins — measured, with no budget attached.** The two forward–backward arms are **complementary, not ranked**: neither refuses input the other accepts, and neither is uniformly cheaper. Growth exponents by doubling pair, `ci/bench/cost-classes.nix`, arms `fbNode` / `fbWork`:

| shape | pairing | `fbNode` list / sets / nrLookups | `fbWork` list / sets / nrLookups |
|---|---|---|---|
| `cycle` (ONE component) | 500→1000 | 2.00 / 1.99 / 1.99 | 1.00 / 0.96 / 0.99 |
| `cycle` | 1000→2000 | 2.00 / 2.00 / 2.00 | 1.00 / 0.98 / 1.00 |
| `fleet` (n components) | 500→1000 | 1.04 / 1.00 / 1.04 | 1.05 / 1.35 / 1.04 |
| `fleet` | 1000→2000 | 1.04 / 1.01 / 1.04 | 1.05 / 1.53 / 1.04 |
| `chain` | 500→1000 | 1.97 / 1.96 / 1.96 | 1.94 / 1.85 / 1.95 |
| `chain` | 1000→2000 | 1.99 / 1.98 / 1.98 | 1.97 / 1.92 / 1.97 |
| `deepwide` | 8000→16000 | 0.02 / 0.04 / 0.06 | 0.04 / 1.02 / 0.07 |
| `deepwide` | 16000→32000 | 0.04 / 0.09 / 0.12 | 0.08 / 1.56 / 0.14 |

Read the two extremes together, because either alone is misleading. **On one large component `fbNode` is quadratic and `fbWork` is linear** — it spends a pivot per node where the worklist spends one per component, and at n = 2000 on `cycle` that is 36,048,017 list elements against 62,018. **On many small components the ranking reverses on the allocation axis**: `fbWork`'s accumulator is a whole-value copy per component, so its `sets` term grows superlinearly (1.35 → 1.53 on `fleet`, and 1.02 → 1.56 on `deepwide`) while `fbNode`, which carries no accumulator at all, stays flat at 1.00–1.01. `chain` is quadratic for both and for the same reason — every pivot's reach set is Θ(n) whichever arm picks it. **No figure here is a budget and none is offered as one**; they are filed with their derivation so the choice between arms is made against measurement rather than against intuition, and they are to be re-derived whenever either construction changes.

**Ceilings, one row per surface the partition and its consumers reach.** A surface with a real ceiling refuses by name at it; a surface with no measured ceiling **states that and refuses nothing**; no ceiling is invented to bound a cost. A "none found to N" row is a bounded claim, not a guarantee, and each row carries its N.

| surface | ceiling | disposition |
|---|---|---|
| `fbNode` | none found to 64,000 atoms on `fleet`, 4,000 on `chain`, 4,000 on `cycle` (one 4,000-member component) | states no ceiling; refuses nothing |
| `fbWork` | none found to 64,000 atoms on `fleet`, 4,000 on `chain`, 4,000 on `cycle` | states no ceiling; refuses nothing |
| `condensationClosure` | **real** — the closure is a capped fixpoint, so it returns iff the cap (1,000 as shipped) is at least the graph's **diameter**, and throws otherwise | refuses **by name**: the message names this surface and the diameter the closure could not reach, not the fixpoint's iteration count. The message, and why only these four surfaces may name a cause, are under *Fixpoint* |
| `dependentsOf` | none found to 256,000 on `chain` (depth 255,999); depth-1 control at 64,000 | states no ceiling |
| `reachableFrom` | none found to 256,000 on `chain`; depth-1 control at 64,000 | states no ceiling |
| `directDependents` | none found to 64,000 | states no ceiling |
| `canReach` | none found to 64,000 | states no ceiling |
| `selfReachable` | none found to 64,000 | states no ceiling |
| `cycles` | none found to **16,000**; above that **not measured** | states no ceiling **and the bound of the claim** |
| `topoOrder` / `topoOrderKahn` | none found to 64,000 | states no ceiling |
| `phaseOrder` | none found to 16,000 | states no ceiling and its bound |
| `coneRank` | none found to 32,000 on `chain` and `deepwide` | states no ceiling |
| `pathsBetween` | **real** — ≈2,498 on `chain` as an UPPER BOUND in a bare expression: uncatchable, depth-driven, and **strictly lower under any open call stack** (three measuring expressions give 2,498 / 2,499 / 2,500 on one fixture, and eight extra evaluator frames above the call move it below 2,497) | a named refusal is **owed and not yet built** |

Two axes are excluded from every "none found" row above and are named once rather than per row. **Shape**: the readings are on `chain`, `fleet`, `cycle`, `star`, `bush` and `deepwide`; dense and complete shapes are not measured for ceilings. **Evaluation context**: a surface that spends an evaluator frame per link has a boundary belonging to the whole evaluation rather than to the surface, so a consumer's real ceiling is strictly lower than a bare-expression reading. Exactly one surface above is frame-per-link (`pathsBetween`), so that axis qualifies that row and leaves the others untouched.

**Provenance, so no row is hand-carried.** The three arm rows and the plain-data property are re-derived in this repository: `./ci/bench/partition-ceiling.sh` (verdict `CEILING-FREE`, with a fixed-depth abort control firing at every cell and the unforced-accumulator construction as a live negative control) and `./ci/bench/partition-plaindata.sh` (verdict `CROSSES`, with the pre-map record shape and a bare function as armed controls that must fail). The `coneRank` row is `./ci/bench/cone-ceiling.sh`. **The remaining rows were measured outside this repository**, by the same instrument shape — the exit code of `nix-instantiate --eval --strict --json` on a separate evaluation, with `okControl` / `catchControl` / fixed-depth `abortControl` in every sweep — and this repository carries no cell that re-derives them. That is stated rather than left to be assumed.

**The calibrated successor, named and NOT armed.** Routing on a cheap pre-partition upper bound — edge count, out-degree distribution — is the calibrated successor to selecting an arm by name. It is decidable when a synthetic configuration of the intended scale exists, and not before: there is no present artefact whose stratum depth stands in for the intended fleet, so a threshold fitted against what exists today would have a domain that does not match the property it quantifies over, and would be uncalibrated by construction. **No bound is proposed here, not even a placeholder** — a number in this contract would be read as the thing to tune rather than the thing to derive.

**`directDependents g`** — the full **direct** reverse-adjacency map `{ id → [direct dependents of id] }`: the immediate reverse neighbours of every node, in one `Θ(n + E)` `groupBy` — it visits every node to read its out-edges, so a node with none still costs its visit. This is the public face of the internal `_reverseIndex`. **Direct**, in contrast to `dependentsOf`'s **transitive** closure — a producer with no consumer simply has no key.

**`directDependentsOf g id`** — the immediate dependents of a single node: `(directDependents g).${id} or [ ]`.

```nix
graph.directDependentsOf g "A"   # → [ "B" ]      (DIRECT — immediate neighbour)
graph.dependentsOf       g "A"   # → [ "B" "X" ]  (TRANSITIVE — full reverse cone)
```

### Ordering

`topoOrder` is **the** ordering front door for the gen ecosystem. Behind it are **two arms**:
Kahn's algorithm (A. B. Kahn 1962; not Gilles Kahn 1974, which `preorder.nix` cites for
something else) over an accessor, and a certificate-gated comparator arm that answers only
where it can prove its answer is the one Kahn's would have given. `entry*`/`phaseOrder` are the home-manager-style authoring layer on top
of it, for consumers that would rather write `before`/`after` constraints than build an
accessor.

```
topoOrder { nodes; edges; keyOf ? id; lessThan ? builtins.lessThan }
    : { ok = true; order = [ node ]; } | { ok = false; cycles = [ [ node ] ]; }
topoOrderKahn <same>      : <same>                     ( the ARM, by name )
coneRank : { edges, ... } → [id] → { order, depth }

entryAnywhere            : entry                       ( {} — no constraints )
entryAfter  [ "a" ]      : entry                       ( comes after "a" )
entryBefore [ "b" ]      : entry                       ( comes before "b" )
entryBetween befs afts   : entry
phaseOrder  { name = entry; ... } : [ name ]           ( forward topological order )
```

**`topoOrderKahn accessor`** is Kahn's algorithm published under its own name, and
**`topoOrder`** is the door, which **selects**. The two are separate because a default is a
separate decision from an algorithm: a caller whose correctness depends on *which* arm
answers binds the arm, and `coneRank` below is exactly such a caller. Everything documented
for `topoOrder` holds verbatim for the arm — same formals, same refusals, same cycle report.

**The selection is invisible in the answer, by construction.** The second arm sorts the nodes
by `(out-degree, key)` and then CHECKS two things about that candidate: that every edge points
strictly backwards in it, and that each element is a direct dependency of the next. The first
makes it a topological order — and, over a total position map, proves the graph acyclic. The
second means every topological order must place those pairs that way, so by transitivity there
is exactly **one** such order and the candidate is it. Where both hold, the door emits what
Kahn's arm would have emitted, necessarily and at every index; where either fails, Kahn's arm
answers. The gate is what makes that true rather than likely: the same candidate emitted
ungated diverges from this door on 1,990 of 2,000 positions on a fleet-shaped graph, and on a
chain whose keys descend with depth it is not a topological order at all.

**What it costs, both ways.** On the dense total order at `n = 2000` the door allocates
**8,026,003** `list.elements` against the arm's **24,082,640** — 2.010 per edge net of the
fixture against 10.042 — and **36,522** `sets.elements` against 21,960,278, because the
comparator arm builds neither the reverse index nor the emission loop. On a shape the gate
refuses, the door pays the check and nothing else: **`2n − 1`** `list.elements` and **`n`**
`sets.elements`, constant in `E`, measured on every refused shape including the dense ones.
★ A caller supplying a `lessThan` that is not a strict total order — the one precondition this
door documents and cannot afford to check — can only produce a candidate the gate REJECTS, so
that precondition is guarded here rather than merely stated.

**`topoOrder accessor`** does **not** throw on a cycle. It returns a producers-first
ordering, or the cycles that prevented one — as strongly-connected-component member sets,
sorted within each component, **all** of them, so a caller sees every cycle at once rather
than fixing one and meeting the next. A self-loop is reported as its own singleton
component. Consumers that build their own diagnostic (gen-pipe names the channels and the
operators forming each edge) need the members, not a throw.

- **`keyOf`** projects a node to its string identity, which is also its tie-break key. It
  is what admits nodes that are not themselves strings — gen-edge orders edge *records* by
  a canonical sort key. **Not** gen-class's `mkClasses { nodes; keyOf; }` argument, which
  shares the name and the `node -> string` shape but plays the opposite role: that key
  *partitions* nodes into share-classes, deliberately mapping many nodes to one key, while
  this one *identifies* a node and a collision in it is a refusal. (`query.nix` also binds
  a local `keyOf` internally; it is not part of any public surface.)
- **`lessThan`** orders those keys. Incomparable nodes emit in ascending key order by
  default; ordering them by a *frozen* key is what makes the result a function of the node
  set rather than of the input permutation. It must be a **strict total order on distinct
  keys** — a documented precondition rather than a refusal, and the only requirement here
  that is not checked. The ready set is a heap and a heap is not stable, so a comparator
  that is not a strict total order can separate this ordering from the one a stable
  whole-array sort would give. Establishing totality means exercising the comparator on
  every pair, Ω(m²) comparisons, which is worse than the cost the heap exists to remove and
  would be paid on every call including the overwhelming majority using the default. Keys
  are distinct by construction — a shared key is already a refusal.
- A `keyOf` output that is not a string, two nodes sharing a key, and an edge naming a node
  outside `nodes` are each a **refusal by name** — a `throw` that `tryEval` can catch, not
  the uncatchable type error those cases would otherwise raise inside `genAttrs`.

**No node-count ceiling.** The Kahn loop is *driven* by a bounded iteration over the key
list rather than by a step that applies itself, so its evaluator frame cost is constant in
`n`. There is no graph size at which ordering aborts with
`stack overflow; max-call-depth exceeded` — an abort `tryEval` cannot catch — and no size at
which the front door declines to order. Measured: a 20,000-node chain orders under
`--option max-call-depth 1000`, twenty times the setting, on every public accessor of both
`topoOrder` and `phaseOrder`. **Cost is the only remaining bound**, and it is no longer a
quadratic one: over `n = 1000 / 2000 / 4000` the loop's allocation grows by ×2.10–×2.12 per
doubling on `list.elements` (exponent 1.07–1.08) and ×1.99–×2.18 on `sets.elements`
(exponent 0.99–1.12), on all four acyclic shapes — read on arm `topoOrderKahn`, which is the
loop by name. Through the door the routed shapes are cheaper than that and the refused ones
are the loop plus `2n − 1`. A large graph gets slower rather than
refused, and it gets slower roughly in proportion to itself.

**None of the loop's three carried structures is a quadratic.** The emitted sequence is held
as *runs* whose lengths are the binary representation of the number of nodes emitted, so
appending is the increment of a binary counter and an element is copied once per carry it
survives: Θ(n log n), where appending to one vector copied `k` elements at step `k` and cost
Θ(n²). The indegree map is a *residue* over a base that is not rewritten — only nodes
decremented but not yet at zero are carried, so on a graph whose indegrees are all one the
residue is empty at every step — and the residue is folded back into a rebuilt base once
carrying it has cost about what rebuilding costs, which is what keeps a graph that satisfies
many nodes partially from paying the same quadratic in a smaller font. The **ready set** is a
leftist heap with O(log m) insert and delete-min, Θ(n log n). Held as a sorted array instead
— rebuilding the unconsumed residue and re-sorting it on every arrival — it was a third,
independent quadratic, and on shapes with out-degree it was the largest single term: 60% of
the loop's `list.elements` on independent pairs, 21% on a fleet of ten-chains, 43% on a
binary tree, and 0% on a chain, whose ready set never holds two nodes at once.

**The heap's price is now the leading set-axis term, as it was predicted to become.** It adds
one attrset per node on each merge path, 63 → 89 attrsets per node across n = 1000 → 8000;
with the indegree map's quadratic gone, that Θ(n log n) term is what the `wide` set axis
mostly is — 427,094 ÷ 4000 = **106.8** `sets.elements` per node at n = 4000, against the
heap's own ~80. It is stated rather than netted, and it is the reason `sets` grows a little
faster than `list` on the shapes with real out-degree.

**The set axis is shape-dependent where the list axis is not**, because it is the one the
indegree residue is charged to: exponent 0.99 on a chain, 1.02 on a fleet, 1.09 on `discrim`,
1.12 on `wide`, and 1.21 off the committed shapes where consumers really do accumulate
waiting on a late common producer. On a driver chain with √n waiters it reads 1.49 — and
there `E` is itself n^1.5, so 1.49 is E-linear and is the floor, not a defect. What keeps
those numbers off a quadratic is *when* the residue is folded back into its base; the `width`
comment in `lib/order.nix` derives the trigger and prices getting it wrong.

**None of this is a claim about dense inputs.** On the total order (`shape=total`, node i
depends on every j > i, E = n(n−1)/2) the loop costs 12.05 `list.elements` per edge at
n = 2000 against 12.01 before the change: unmoved, because both accumulators are already
small there and what dominates is the reverse index — 4.00 per edge, 36.3% of the total —
which neither remedy touches.

★ **That 12.05 is GROSS, and on this shape the distinction is load-bearing.** `total`'s fixture
is Θ(n²) by construction, so `arm=floor` is not a rounding error here the way it is on every
sparse shape — it is 2.01 of the 12.05. **Net of the floor the loop costs 10.04 `list.elements`
per edge**, and the per-edge figure *falls* across the sizes measured — 10.15 / 10.08 / 10.04 at
n = 500 / 1000 / 2000, with `sets` 11.02 / 10.99 / 10.98 and `nrLookups` 7.21 / 7.11 / 7.05. A
flat-to-falling cost per edge on all three axes is the statement that this surface is **Θ(E)**,
i.e. **linear in the input it is given**, and a dense input is simply a large one. Quote whichever
figure you like, but quote which: 12.05 and 10.04 are the same measurement, and a budget compared
against the wrong one is comparing a library to a fixture.

Re-run, and the figures above have **two different producers**, split by whether they are a
reading or a comparison. The growth rates and the per-node counts are readings of the shipped
library: `ci/bench/cost-classes.nix`, arm **`topoOrderKahn`** — the loop by name, which is what
these figures are about; arm `topoOrder` is the door and answers a routed shape with the other
arm — at `n = 1000 / 2000 / 4000`. The
**shares and deltas** — the ready set's 60% / 21% / 43% / 0%, and the heap's 63 → 89 attrsets
per node — are comparisons between **two revisions of this library**, and the array ready set
exists at neither the tip nor in any arm of `ci/bench/cost-classes.nix`, so no command in this
repository produces a share or a delta, and none can. Those come from the committed
two-revision harness: `den-architecture`,
`specs/2026-08-08-gen-graph-ready-set-quadratic.r1-*`, whose `.r1-data-note.md` carries the
procedure, the pinned revisions and the md5 anchors. The **1.21 and 1.49 exponents** have a
third producer again: their shapes are in no arm of this bench, and they are recorded with
`den-architecture`, `specs/2026-08-09-gen-graph-accumulator-remedies-spec.md`, alongside the
arm-against-arm measurement the residue's fold trigger is derived from. **Post-change** cells
— what the shipped `topoOrder` costs on any shape, as it stands — come from
`ci/bench/cost-classes.nix`, arm `topoOrderKahn`, shapes `wide` / `fleet` / `discrim` / `total` /
`deepwide`. ★ Before quoting a
`sets.elements` figure from that bench, read `ci/bench/sentinel.sh`: `sets` figures are
comparable only within one revision of the bench file, and the sentinel is what says which
revision you are on.

**`coneRank g cone`** — producers-first topological rank of a node set, computed
**cone-locally**. Returns `{ order; depth; }` where `depth id = 0` if `id` has no producer
inside `cone`, else `1 + max(depth of its in-cone producers)`, and `order` is `cone` sorted
ascending by depth with an id tie-break (so every producer precedes its consumers).
Memoized via `lib.fix` over the cone, so it runs in O(|cone| + edges-in-cone) — it does
**not** materialize the whole-graph `condensation`. This is RTD 1983 topological rank
restricted to a dependent cone.

```nix
graph.coneRank g [ "A" "B" "X" ]    # for B→A, X→B
# → { order = [ "A" "B" "X" ]; depth = { A = 0; B = 1; X = 2; }; }
```

**No ceiling, and a cyclic cone is a named refusal.** Both used to be otherwise, and both
came from the same place. The memo map is forced along a topological order of the cone,
taken from `topoOrderKahn` — the arm by name, so that a future default cannot make the rank
recurrence call itself. Forcing in that order flattens what was a descent: reading the
deepest node first used to walk the cone one evaluator frame per link and abort with
`stack overflow; max-call-depth exceeded`, uncatchably, at a 3,998-node chain and at every
size of a graph with a 4,000-deep leg. **No ceiling found to 32,000** on either shape, so
this surface states that and refuses nothing at a size — re-run
`./ci/bench/cone-ceiling.sh`, which runs the pre-remediation construction beside the
current one at every cell and reports INVALID if that control does not abort.

The cone no longer has to be acyclic. The ordering call that supplies the warming order is
the same call that reports a cycle, and its **verdict is read before the memo map is
entered**, so a cyclic cone is a `throw` naming the cycle instead of an uncatchable
`infinite recursion encountered`. The order of those two steps is the requirement, not
merely that the driver exists: `./ci/bench/cone-consultation.sh` is one construction with a
single switch on consultation order, and the late arm dies on a cyclic cone while returning
the same order as the early one on an acyclic cone.

The price is one ordering pass, filed rather than accepted silently:
`ci/bench/cost-classes.nix`, arms `coneRank` and `coneRankShipped`.

**`phaseOrder entries`** is the throwing convenience layer over `topoOrder`: it returns
**a** valid topological order, and throws on a cycle or a self-loop, preserving the
contract gen-dispatch's `dag.nix` had.

**Behaviour change — an unknown phase name is now a refusal, and used to be ignored.** An
`after` or `before` naming a phase that is not a key of `entries` previously composed
fine, with the constraint silently dropped: `phaseOrder { a = entryAfter [ "ghost" ]; b = entryAnywhere; }` returned an order treating `a` and `b` as independent. It now throws a
named refusal. A constraint that cannot be honoured is a caller error, and dropping it
returns a confidently wrong order rather than no order.
For genuinely *independent* nodes the tie-break is
ascending name, but treat the result as a valid order rather than a specific permutation —
a consumer that applies a phase's effect only *after* the phase (so later phases see
earlier results, never the reverse) is output-invariant across any valid order.

**Edge direction, stated once.** `edges u ∋ v` means "u depends on v" (consumer →
producer), so an ordering is producers-first. Every ordering surface in this library reads
an accessor this way — `topoOrder`, `coneRank`, `condensation.bottomUp`, `dependentsOf`,
`reachableFrom` — and so does `phaseOrder`'s internal construction: `after = [ d ]` on `n`
builds the edge `n → d`.

```nix
graph.phaseOrder {
  validate = graph.entryAnywhere;
  resolve  = graph.entryAfter [ "validate" ];
  emit     = graph.entryAfter [ "resolve" ];
}                                         # → [ "validate" "resolve" "emit" ]
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
fixpoint            : { seed, step, maxIter?, refusal? } → edgeMap
seededFixpoint      : { seed, frontier, step, maxIter? } → edgeMap
compose             : edgeMap → edgeMap → edgeMap
closureClass        : [ surfaceName ]
closureOf           : surfaceName → { edges, nodes, maxIter?, ... } → edgeMap
transitiveClosure   : { edges, nodes, maxIter?, ... } → edgeMap
transitiveReduction : { edges, nodes, maxIter?, ... } → edgeMap
```

**`fixpoint { seed, step, maxIter?, refusal? }`** — iterates `step` on `seed` until the result stabilizes (`next == current`). Throws if the step is non-monotonic (result shrinks) or exceeds `maxIter` (default 1000).

**The cap's refusal names no cause, and that is deliberate.** Reaching `maxIter`, this binding has observed two things — the cap was reached, and the step never shrank — and `step` is yours, so it cannot know which of two unrelated constructions it is holding: a monotone step whose ascending chain is longer than the cap, or a step that oscillates without changing cardinality, which the monotonicity guard cannot see because cardinality is not the subset order. The message therefore reports the observation and stops. `refusal` is how a caller whose `step` is fixed supplies its own reading: it receives the cap that was exhausted and returns the message to throw.

**`closureClass` / `closureOf surfaceName`** — `transitiveClosure`, `dependents`, `condensationClosure` and `transitiveReduction` each make one closure call, so they share one cost curve (see *The closure class* under Performance), one ceiling, and one refusal. `closureOf` is that shared construction, named by the surface calling it; `closureClass` is the enumeration it accepts, and a surface off that list is refused rather than allowed to emit a refusal naming a surface the library does not have. Every member forwards a `maxIter` set on its own argument record to the fixpoint, so a caller who knows their graph's depth can state the budget the refusal will quote back.

Because the closure's `step` is `unionEdges current (compose current mat)`, it only ever grows — it is monotone on the **subset** order, not merely on cardinality — so the oscillating cause above cannot arise there, and reaching the cap can only mean an ascending chain that has not converged. For reachability that chain's height is the graph's **diameter**, so these four refuse with it by name:

```
gen-graph: dependents: the graph's reachability diameter exceeds 1000, the closure
fixpoint's iteration cap. The closure step is monotone on the subset order by
construction, so an unconverged closure at the cap is depth and nothing else.
```

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
fromScan     : { items, scan, project, nodeData? } → accessorRecord + { derivedEdges }
field        : name → id → entry → [id]
fields       : [name] → id → entry → [id]
fixtures     : { diamond, chain, cyclic, tree, serviceGraph, disconnected }
labeledFixtures : { world, cyclic, poisoned }   # { labeledEdges; nodes; } for labeled queries
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

**`fromScan`** — the graph a **reference scan** derives. Where `mkGraph` takes an edge list you already have, `fromScan` takes the values and *constructs* one: `items` are `{ id; value; }` pairs, `scan` reads the references out of a value, and `project` maps a reference to the id it names. The dependency structure is then a function of the values alone, knowable before any of them is used — Mokhov, Mitchell & Peyton Jones, *Build Systems à la Carte* (ICFP 2018) §3, applicative task dependencies.

```nix
g = graph.fromScan {
  items = [
    { id = "theme:font"; value = { size = mkRef "terminal:size"; }; }
    { id = "terminal:size"; value = { }; }
  ];
  scan = v: builtins.filter isRef (builtins.attrValues v);
  project = r: r.target;
  nodeData = { "theme:font" = { field = "font"; }; };
};

g.edges "theme:font"                  # → [ "terminal:size" ]
graph.cyclePaths g                    # → [ ]
g.derivedEdges                        # → [ { from; to; item; ref; } ]
```

Nothing here knows what a reference is: `scan` and `project` arrive as arguments, so the scanned domain's vocabulary never enters gen-graph, and ids stay opaque strings — the compound `"<identity>:<field>"` addresses above are never split. Two contract points. `nodeData`'s keys **seed** nodes and items do not, so an item the scan finds nothing in, and that nothing references, is absent unless you name it. And `derivedEdges` comes back beside the accessor carrying the `item` and the `ref` behind each edge — that is where a caller reads a reference's own payload, instead of running the scan a second time.

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

### Labeled Queries

The label-blind surface above (`edges : id → [id]`) is untouched; labeled queries are a
layer for graphs whose edges carry a **kind**. A labeled graph is `{ labeledEdges; nodes; }`:

```
labeledEdges : id → [ { label; target; } ]
nodes        : [ id ]
```

Reachability is then constrained by a **regex over labels** — a query answers a node iff the
word spelled by the labels along some path from `from` matches the `follow` expression.

**`labeledFrom { perLabel; nodes; }`** adapts one plain accessor per edge kind into the
labeled contract:

```nix
g = graph.labeledFrom {
  nodes = [ "root" "h1" "u1" "g1" ];
  perLabel = {
    contains = id: containsEdges id;   # each returns a plain [ id ] list
    member   = id: memberEdges id;
  };
};
```

**`nodes` is a required formal, and that is breaking** — the constructor used to take the
per-label map alone. A labeled query is *seeded*: it starts `from` a node and walks, so it
never needed a domain. Every global surface is *node-set-total* and cannot work without
one, and an accessor's domain is not enumerable, so a node set omitted at construction
cannot be recovered afterwards — the global half was simply unreachable from a labeled
graph, and the way that got reported was an arity abort deep inside a callee, which
`tryEval` cannot catch. A **default** would have made the same failure silent: every global
surface would answer, about a domain the caller never stated.

**`forgetLabels g`** is the one published bridge, `labeledGraph → { edges; nodes; }`. Every
global surface composes with a labeled graph through it and only through it. Parallel edges
differing only in label collapse, because the plain accessor is a set of targets — the same
contract `mkGraph` states.

```nix
graph.condensation (graph.forgetLabels g)   # SCC partition of a labeled graph
```

**`labeledTranspose g`** reverses every edge **and carries its label**, so a reverse read is
the forward construction over a transposed accessor with `follow`, `order` and `groupBy`
untouched — one construction with a direction argument, not two that can drift apart.

```nix
query { graph = g;                        from = "root"; follow = regex.parse "contains+"; }
query { graph = graph.labeledTranspose g; from = "u1";   follow = regex.parse "contains+"; }
# → what root contains         /         → what contains u1
```

Mokhov 2017 §5.2's law is that transpose flips the arguments of `connect` and leaves
`overlay` unchanged: direction is **reversed, not erased**. Going through `forgetLabels` to
reach the plain `transpose` erases exactly the component a label regex reads, which is why
this is not sugar for that composition. It is Θ(n + E) — one accessor pass, one `groupBy`,
shared by every lookup and not forced at all if the transposed graph is never queried — and
it is expressible only because `nodes` is a required formal: reversal asks who points **at**
a node, which an accessor's non-enumerable domain cannot answer alone.

**`boundedBy g marksOf`** applies per-node **boundary marks** to a labeled graph, yielding a
labeled graph plus a companion diagnostic. A mark is `{ name; admits; }` — a name the
diagnostic can quote and a `label → bool` predicate. `marksOf : id → [ mark ]`, and an
unmarked node returns `[ ]`.

```nix
b = graph.boundedBy g (
  id: if id == "gate" then [ { name = "sealed"; admits = l: l == "e"; } ] else [ ]
);

b.labeledEdges "gate"   # → [ { label = "e"; target = "ok"; } ]         the admitted edges
b.withheld     "gate"   # → [ { label = "q"; target = "no"; marks = [ "sealed" ]; } ]
```

The construction only ever **removes** edges, so a caller holding the bounded graph has no
operation that recovers a withheld one: widening is not forbidden, it is unsayable. That is
also why marks are applied at the accessor rather than inside the label regex — `deriv`
takes a label and an expression and never sees a node, so a per-node intersection is not
expressible there at all. **`withheld` is not optional**: a filtering accessor that said
nothing would answer a boundary and an absent edge identically, and those two must not be
indistinguishable in the diagnostic as well as in the answer. An edge withheld by several
marks is one entry naming all of them — picking one would make the report depend on mark
order.

**`cyclicEdgesWhere g p`** — the edges whose label satisfies `p` **and** which lie on a
cycle, as `[ { from; label; to; } ]` sorted by `(from, label, to)`. Empty means no cycle of
this graph carries such an edge. It completes the family `cycles` (which *nodes*) and
`cyclePaths` (which *walk*) with *which edges satisfying p*.

```nix
graph.cyclicEdgesWhere g (l: l == "neg")
# → [ ] , or e.g. [ { from = "c"; label = "neg"; to = "a"; } ]
```

The construction is the composition the total contract exists for: forget the labels,
partition the projection into strongly connected components, then join back onto the
retained labelled edges — two endpoints in one component are mutually reachable, so the
edge between them closes a cycle, and a self-loop is one already. That decomposition is
**ABW 1988's own proof method** for Lemma 1's converse, not a construction that agrees with
it. The predicate is the caller's: this library is label-agnostic and does not know which
labels are special, so it answers about the graph and leaves the meaning of an empty answer
to whoever supplied the predicate.

**`regex`** builds `follow` expressions, as constructors or a compact string:

```
regex.lit / seq / alt / star / opt / plus / any / eps / empty   # constructors
regex.parse : string → regex                                     # compact form
```

Grammar (`parse`): whitespace = sequence, `|` = alternation (binds loosest), postfix `*` `?`
`+`, parentheses group, `_` is the any-label wildcard, labels are `[A-Za-z0-9_-]+`, and `""`
parses to `eps`. Postfix is whitespace-insensitive — `a *` is `a*`. Malformed input throws a
named `gen-graph.regex.parse: …` error.

```nix
regex.parse "contains* member"          # zero-or-more contains, then one member
regex.parse "own | include owni"        # a declaration here, or one hop through an include
```

> **Label alphabet caveat.** Regex composites render to a canonical `stateKey` for the
> derivative seen-set. A constructor-supplied `lit` label containing rendering metacharacters
> (`* | . ( )`) can collide with a composite's rendering, so `lit` labels are expected to match
> `[A-Za-z0-9_-]+` (the `parse` alphabet). Callers own this constraint (see the `regex.nix`
> header).

**`query`** runs a labeled query in one of five modes:

```
query : { graph; from; follow; where?; mode?; order?; groupBy?; … } → result
```

| Mode | Result | Notes |
|------|--------|-------|
| `all` (default) | sorted `[ id ]` | reachable set; `from` included iff `follow` is nullable. `genericClosure` over the (node × derivative-state) product — scales, no path materialization |
| `paths` | `[ { node; path = [ { label; from; to; } … ]; } ]` | labeled path **witnesses** (the "why"); acyclic paths only |
| `visible` | `{ visible; shadowed; }` | nearest-wins resolution under `order`, grouped by `groupBy` (default: the answer node) |
| `layers` | `[ [ answer … ] … ]` | all answers grouped into ordered layers by rank word (the cascade shape) |
| `fixpoint` | fold result | dispatch-alias for `queryFold` (below) |

`order = { labels = [ … ]; endOfPath ? -1; }` gives a per-query specificity order: earlier
labels are more specific, unlisted labels rank after all listed. `endOfPath` is the rank of
*stopping* — the default `-1` makes a proper prefix beat its extensions (prefix-wins); a higher
rank lets continuation on lower-ranked labels beat stopping.

```nix
query {
  graph = g;
  from = "s";
  follow = regex.parse "own | include";
  mode = "visible";
  order.labels = [ "own" "include" ];   # own shadows include
}
# → { visible = [ … own answers … ]; shadowed = [ … include answers … ]; }
```

**`queryFold`** folds a caller-supplied combine over the `all`-mode answer set in canonical
sorted order (the group-closure / acl shape):

```nix
queryFold {
  graph = g;
  from = "admins";
  follow = regex.parse "includes* member";
  empty = [ ];
  combine = acc: u: acc ++ [ u ];
  # valueOf ? (id: id), where ? (_: true)
}
```

`combine` is expected to be a commutative-idempotent monoid; under those laws the canonical
order is unobservable. Recursive node-valued fixpoints (a node's value depending on its
neighbours') remain [`fixpoint`](#fixpoint) territory.

**`queryArrivals`** walks the same product automaton as `all` and differs from it in exactly
two ways, both of which are the point: it is keyed on the **arriving edge** rather than the
node, and it returns a **sequence** rather than a set.

```nix
queryArrivals {
  graph = g;
  from = "s";
  follow = regex.parse "a | b";
  advance = s: s.distance + 1;    # REQUIRED — the per-step distance rule
  # where ? (_: true)
}
# → [ { node = "x"; distance = 1; via = { from = "s"; label = "a"; }; admission = "e"; }
#     { node = "x"; distance = 1; via = { from = "s"; label = "b"; }; admission = "e"; } ]
#   ("e" is stateKey's rendering of eps — nothing further is admitted here; a literal
#    label `e` would render `'e`)
```

`all` answers that query `[ "x" ]`. Its seen-key is ⟨node, derivative-state⟩ and an
alternation derivates both labels to the same state, so the second edge vanishes with
nothing in the answer to say it existed. Keying on ⟨arriving edge, derivative-state⟩ keeps
both, and termination is untouched: edges are finite and derivatives are finite modulo the
ACI identities `regex.nix` normalizes by, so the refined key set is still finite and still
fences cycles — refining a fence does not remove it. The price is the in-degree factor
(|E| × |derivatives| against `all`'s |V| × |derivatives|), which is why `all` keeps its own
contract and this is a separate surface rather than a replacement. There is no
`listToAttrs`/`attrNames` round trip either, so answers come out in visitation order with no
reorder and no node-level dedup after the walk.

`advance : { distance; from; label; to; } → int` is **required**. It is handed the distance
already accumulated at the step's source together with the step, and returns the distance
after it; plain hop count is `s: s.distance + 1`. A graph that reifies a relation as a node
with labelled incidence — one relation spelled as two edges through the reified node — can
write a rule that does not charge the edge completing the pair, so that a representation
choice does not silently move a distance. It has no default: a defaulted distance rule is a
semantics nobody wrote down.

`via` is `null` at the root (it arrived by no edge, and saying so is a statement rather than
a missing field) and `{ from; label; }` everywhere else. `admission` is the canonical key of
the residual `follow` expression at the arrival — the admission policy still in force there,
and the component a caller needs to state a ⟨node, state⟩ collapse of its own.

> **`distance` is a first arrival, not a minimum, and the bound is sharp.** `genericClosure`
> keeps the first item inserted under a key. That first arrival *is* the minimum when
> `advance` is nondecreasing in hop count — visitation is nondecreasing in depth, which
> `ci/tests/closure-order.nix` asserts against a seeded depth-first control — so plain hop
> count and every positive-constant rule are safe. Under a rule that can charge **zero** it
> is not: a longer route charging zero on some hops can total less, and the shorter one is
> visited first. Whether the cheaper arrival survives at all depends on its **last** edge —
> entering by a different final edge it is kept beside the dearer one and a caller can fold
> the minimum out of the sequence; entering by the *same* final edge in the same state it
> shares the key and is discarded, and then no fold of this sequence recovers it. A true
> minimum under a zero-charging rule needs a relaxing traversal, which this is not.

**gen-scope adapter recipe** (recipe only — gen-graph does **not** import gen-scope):

```nix
# consumer code: wrap gen-scope's per-label followEdge into the labeled contract
g = graph.labeledFrom {
  nodes = scope.allIds self;           # the domain, stated: absence is not a default
  perLabel = {
    imports = id: scope.followEdge "imports" self id;
    parent  = id: scope.followEdge "parent" self id;
  };
};
```

**Cost guidance.** `all` is `genericClosure`-backed and scales (no path materialization).
`paths`/`visible`/`layers` enumerate witnesses and are enumeration-priced — use them when the
witness itself is the product. The two families also differ observably: `all` answers node
revisits (the (node × state) product), while witness modes enumerate acyclic paths only, so a
self-loop witness that `all` reports is not enumerated by `paths`.

## Usage Example

```nix
{ gen-graph }:
let
  graph = gen-graph.lib;

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
| `reachableFrom` | `Θ(Σ_{u ∈ reach s} (1 + outdeg u))` — i.e. O(reachable) only where out-degree is **bounded**; Θ(n²) on a complete DAG | C-level BFS via `builtins.genericClosure`. The per-visit cost is O(1 + outdeg), not O(1), because the `genericClosure` operator re-reads `edges` at every visit |
| `reachableWhere` | exactly the `reachableFrom` cost above — O(reachable) only at bounded out-degree, Θ(n²) on a complete DAG | same C-level BFS, filter applied after |
| `canReach` | `Θ(Σ_{u ∈ visited} (1 + outdeg u))` from the source `s`, where `visited` is `reach s` **less the nodes the target dominates** — same operator, same per-visit cost, over fewer visits. O(reachable) only at bounded out-degree and Θ(n²) on a complete DAG | C-level BFS that **stops expanding at the target**; the target still enters the closure, so the answer is unchanged. ★ **Scoped**: Θ(n) → Θ(1) on a one-hop chain query, unchanged on a complete digraph where the target dominates nothing. Measured as a pair against the full walk in `ci/bench/canreach-exit.nix`; the exit costs one key comparison per visit, which is what the `far`/`miss` cells price |
| `selfReachable` | `Θ(Σ_{u ∈ reach v} (1 + outdeg u))` from the node `v` — same operator, same per-visit cost, so O(reachable) only at bounded out-degree and Θ(n²) on a complete DAG | C-level BFS checking self-reappearance |
| `hoistEdges` | `Θ(n)` spine, paid once and eagerly; then `Θ(1 + outdeg u)` per node **on first lookup**, so `Θ(n + E)` only if every node is looked up | builds a `builtins.listToAttrs` spine over `nodes` whose values are **unforced thunks** — a node's `edges` call and its wrapping happen when the traversal first reaches it, never for a node it does not. This is the whole out-degree factor of the three rows above, lifted out of the **per-visit** path and charged **per node** instead |
| `reachableVia` / `selfReachableVia` | `Θ(\|reach s\|)` attrsets per traversal, **on top of** the one `hoistEdges` charge — so `k` traversals over one accessor cost `Θ(n + E) + Θ(k · \|reach\|)` where the unhoisted pair cost `Θ(k · Σ (1 + outdeg))` | the same two closures with the wrapping hoisted. ★ **Worth it only for large `k`**: at `k = 1` the caller still pays the whole `Θ(n)` spine while the traversal reads only the nodes it reaches, so a single-traversal caller is strictly worse off — measured on `dependentsOf`'s row below, where the penalty is **2–3 allocations per node, flat in n on every shape**, and is not the unread edges |
| `ancestorsOf` | O(depth) | single-path walk |
| `pathsBetween` | O(paths × depth) | exponential in path count; use on small subgraphs |
| `materialize` | O(nodes × avg degree) | one-time scan |
| `transitiveClosure` | **closure class** (see below) | fixpoint over materialized map |
| `transitiveReduction` | **closure class** unless *every* node has out-degree ≤ 1 (see below) | needs full closure; O(1) membership via attrsets |
| `cycles` | `Θ(n + E)` to read the accessor once, then `Θ(Σ_v \|reach v\|)` for the n closures — i.e. O(nodes × reachable) with the out-degree factor paid **once** rather than at every visit, so Θ(n²) on a complete DAG and no longer Θ(n³) | per-node C-level BFS — one closure per node, so no whole-graph transitive closure. It spends n closures on one accessor, so it binds `hoistEdges` and the operator no longer re-reads `edges` per visit. Measured at `complete` n = 400: exponent **3.00 → 2.00 on both `list` and `sets`**, 200.5× fewer list elements and 395.2× fewer attrsets, while `nrLookups` moves 0.08% — a lookups-only budget scores this a no-op. `ci/bench/cost-classes.nix`, arms `cycles` / `cyclesUnhoisted` |
| `cyclePaths` | on a DAG, exactly the `cycles` cost above — so Θ(n²) on a complete DAG; + the `fbNode` partition arm (see its own row) and simple-path search once cyclic | short-circuits before any path work when acyclic. Builds no closure of its own, so it inherits both callees' hoist and nothing else: measured 1.95× fewer attrsets on `cycle` at n = 400, arms `cyclePaths` / `cyclePathsUnhoisted`. **The cyclic branch is not priced by those arms** — it runs `pathsBetween`, which enumerates every simple path, and no arm here quantifies it on a dense component |
| `dependents` | **closure class** (see below) | full transitive closure + transpose |
| `dependentsOf` | `Θ(n + E)` for the reverse index, then `Θ(Σ_{u ∈ reach⁻ t} (1 + indeg u))` for the walk — i.e. O(reachable) only where **in**-degree is bounded; Θ(n²) on a complete DAG | reverse index + C-level BFS. The walk is the `reachableFrom` operator run over the reversed index, so its per-visit factor is the forward in-degree. ★ **It does not hoist the accessor**: one closure has no second traversal to spread the wrap's `Θ(n)` spine over, and that spine is built whether or not the walk reaches the node. Measured **worse** hoisted on every shape — 1.003× on `complete`, 1.32× on `cycle`, 1.35× on `chain`, 1.41× on `fleet`. The margin is `3n + 1` on `chain`/`fleet`, `3n` on `cycle` and `2n + 2` on `complete` — exact at every n measured: **2–3 allocations per node, flat in n on every shape and independent of E**, which is what says it is the spine and not the unread edges — on `complete` nothing is unreached at all and the margin is still `2n + 2`. Arms `dependentsOf` / `dependentsOfHoisted` |
| `dependentsFrontier` | the row above **restricted to what `prune` admits**, and nothing else: `Θ(n + E)` for the reverse index, then `Θ(Σ_{u ∈ expanded} (1 + indeg u))` for the walk — a pruned node is reached without paying its in-degree. **One term, no accumulator term**, so at `prune = _: true` it is `dependentsOf`'s law and not merely bounded by it | reverse index + C-level BFS with the prune moved **into the operator**. ★ **Inclusion and expansion are two separate moments in `genericClosure`** — a node enters the closure when its PARENT emits it and the operator runs on it only afterwards — so an operator returning `[ ]` includes a pruned node without expanding it, and the early cutoff needs neither a level walk nor a visited attrset; the C-level done set is the cycle guard. Measured on `chain` (in-degree exactly 1, so nothing here is an in-degree effect), n = 100 → 800: `sets` exponent **1.80 → 0.89** net of the fixture floor and `nrOpUpdateValuesCopied` **40,508 → flat 110**, landing on the `dependentsOf` control **within one attrset at every n** with `list` bit-identical to it. Arms `dependentsFrontier` / `dependentsFrontierPruned`, paired with `dependentsOf` on the same shape and `n` |
| `coScc` | the `canReach` cost paid from each of `u` and `v`, each probe over its own start's reachable set **less what its own target dominates** — O(reachable) only at bounded out-degree, Θ(n²) on a complete DAG. ★ **This is the CALLER's figure, not the library's**: it is derived from `canReach`'s operator law above, and **no bench arm measures it** | two `canReach` probes, each stopping at its own target — two closures, so what is avoided is the whole-graph transitive closure and each probe's dominated remainder, not the rest of the per-probe one. ★ **Export-only — nothing in `lib/` pays this.** The `condensationClosure` arm decides co-SCC from its own closure rather than through this name, and `coScc` is in turn `canReach`'s only caller in `lib/`, so the two probes sit off every internal cost path. What a caller pays scales with its own pair count, since each pair re-materializes both closures |
| `condensation` / `fbNode` | quadratic in the members of ONE component and linear in components: `list`/`sets`/`nrLookups` exponents 2.00 on `cycle`, 1.00–1.04 on `fleet`, ~1.98 on `chain` (n = 500 → 2000) — **all three re-derived and unmoved by the accessor hoist**, which changes the DENSE reading those shapes cannot see: on `complete` (n = 200 → 400) `sets` runs **2.98 → 2.00**, 62.2× fewer attrsets at n = 400. ★ **`list` there now drops the same full exponent, 2.97 → 2.00**, where it once stayed cubic at 2.86 under the hoist. The residue that kept it there was the `foldl'`-with-`elem` dedup `edge-maps.materialize` called per node, and it left with the `gen-prelude` dedup bump; it was **not** `prelude.concatMap`'s `++` inside the shared finisher, which an earlier reading of this row named and which is `builtins.concatMap` | two `genericClosure` calls per node, no accumulator, no recursion. 2n closures over two accessors, so it binds `hoistEdges` on each and the operator no longer re-reads `edges` per visit. **No closure call and no fixpoint**, so no iteration cap to inherit. Arms `fbNode` / `fbNodeUnhoisted`. Ceilings and the arm comparison: *The partition routing contract* above |
| `fbWork` | the mirror image: 1.00 on `cycle`, but its accumulator is a whole-value copy per component, so `sets` runs 1.35 → 1.53 on `fleet` while `list`/`nrLookups` stay at 1.04–1.05 | one forward–backward pass per COMPONENT over a `foldl'` accumulator. Complementary to `fbNode`, not ranked. ★ **It does NOT hoist its accessor, though it makes many closures**: hoisting builds a whole-graph `Θ(n)` memo up front, and this arm's closures **partition** the graph rather than re-covering it — each round walks a subgraph the earlier rounds have shrunk — so there is no second traversal over the same edges to spread that build cost over. Same mechanism as `dependentsOf`'s negative cell below. Measured 4.12× better on one deep `chain` (the one shape whose backward walk re-covers the whole unassigned tail every round) and 1.003–1.25× **worse** on `complete`, `fleet`, `wide`, `total` and `cycle`, the decisive losses being `cycle` (1.243×) and `complete`'s `nrLookups` (1.397×). ★ **Restriction ordering is not the lever**, measured: an arm memoizing plain adjacency and restricting *before* wrapping recovers none of it — worst of three on `fleet`, and within 4 sets of the full hoist on `cycle` while both memoizing arms sit ~2,400 above the shipped one. Arms `fbWork` / `fbWorkHoisted` |
| `condensationClosure` | **closure class** (see below) | one transitive closure. The second closure over the quotient is gone — every arm now takes its `bottomUp` and `depth` from one `coneRank` pass over the condensation instead, which is `topoOrderKahn`-warmed and reaches no fixpoint |
| `coneRank` | `O(\|cone\| + edges-in-cone)` for the recurrence, **plus one ordering pass** — `list` exponent 1.07 on `chain` and `fleet`, `sets` 1.00–1.02, `nrLookups` 1.00–1.06 (n = 1000 → 8000) | `lib.fix` memoized depth, cone-local (no condensation), warmed along `topoOrderKahn`'s order. **No ceiling found to 32,000** on `chain` or `deepwide`; a cyclic cone is a named refusal. The construction it replaced is linear on all three axes and aborts past ~4,000 on `chain` — `ci/bench/cost-classes.nix`, arms `coneRank` / `coneRankShipped` |
| `topoOrder` / `phaseOrder` | O(n + E) decrements through the Kahn arm, and **near-linear in allocation** — exponent 1.07–1.08 on `list.elements` and 0.99–1.12 on `sets.elements`, all four acyclic shapes, read on arm `topoOrderKahn`. ★ Through the DOOR a shape the certificate admits is cheaper by a class of construction rather than a constant — `18n` on a chain against the loop's 1.07 exponent, 2.010 `list`/edge against 10.042 on the dense total order — and a shape it refuses is the loop plus `2n − 1` | nothing the loop carries is quadratic: the emitted sequence is a binary-counter run list (Θ(n log n)), the indegree map is a residue over a rebuilt base, and the ready set is a leftist heap (Θ(n log n)), where a re-sorted array was a third quadratic worth 60% of the `wide` list allocation. The heap's `sets.elements` price, 63 → 89 attrsets per node over n = 1000 → 8000, is now the leading set-axis term. No frame ceiling — the loop is a bounded iteration, so no node count aborts or is refused |
| `directDependents` / `directDependentsOf` | `Θ(n + E)` | one `groupBy` reverse-adjacency map — this is `_reverseIndex`, whose `concatMap` visits every node, so a node with no out-edges still costs its visit |
| `seededFixpoint` | O(work per delta) | semi-naive: each iteration touches only the frontier |
| `roots` / `leaves` | O(nodes × avg degree) | single scan of all edges |
| `select` | O(nodes) | one pass over node list |
| `unionEdges` / `intersectEdges` / `differenceEdges` | `Θ(keys + entries)` over both maps for `intersectEdges` and `differenceEdges`; `unionEdges` adds a per-key `Θ(m log m)` in that key's combined target count `m` — `Θ(m)` on the list axis, the `log m` being comparisons | both maps are walked by `attrNames`, so a key with an empty target list still costs its visit. `intersect`/`difference` test membership in an attrset, O(1) per edge; `unionEdges` instead calls `prelude.unique` per key, which on a string target domain dedups by sorting first-occurrence indices. ★ **The quadratic this row used to name is not gone, it is domain-scoped**: `prelude.unique` keeps the `foldl'`-with-`elem` fold as its non-string fallback, so a caller whose targets are not strings still pays `Θ(m²)`. Edge targets are node ids, so the shipped path is the linear one. Measured on one key with m distinct string targets in both maps, m = 250 / 500 / 1,000: **3,007 / 6,007 / 12,007** list elements, exactly `12m + 7`, exponent **1.00** — against **126,756 / 503,506 / 2,007,006** and exponent **2.00** before the `gen-prelude` dedup landed, a factor of **167× at m = 1,000** that doubles with every doubling of m. The set axis takes the other side of that trade: flat at 313 before, `6m + 313` now |

**The closure class.** `transitiveClosure`, `dependents`, `condensationClosure` and `transitiveReduction` each cost one `fp.closureOf` call, and on **`list.elements`** they measure as **one curve**, not four costs. ★ **That axis is where the class reads cleanest; it is no longer where the bill is.** Before the `gen-prelude` dedup bump the `list` term at n = 200 exceeded the other two counters combined by 417× on the complete digraph and 124× on the cycle, and the class was stated on `list` for that reason. The bump traded the dedup's list allocation for attrsets, and at the same n those ratios are now **0.68× on the complete digraph and 0.69× on the cycle** — `sets` is the larger term on both. The class still reads as one curve on `list`, and it now reads as one curve on `sets` as well. On a complete digraph the growth **exponent** is ~2.95 for all four and the exponents agree to 0.50% (2.947–2.962); the **raw** figures agree an order closer only for the first three (0.730% apart at n = 200), while `transitiveReduction` sits 1.09% above `transitiveClosure` — the 0.50% is a statement about exponents, not about allocation counts. `transitiveClosure` alone is 99.6% of `dependents`. On a simple cycle the first three are ~2.93, and their spread **narrows** with n — 1.651% at n = 50, 0.891% at n = 100, 0.464% at n = 200 — so the class claim strengthens as the graph grows rather than holding at one fixed bound. *Spread* here is `max ÷ min − 1` over the members compared, stated because the figure is meaningless without it. It is **super-quadratic on both shapes — not the O(nodes²) once documented here.** This is practical scaling guidance, not an identity on every axis — though the axis that used to break the identity no longer does: on `sets.elements` the complete-digraph exponents once separated, `transitiveClosure` at 0.74 against 1.93–1.99 for its siblings, and under the dedup bump and the squared schedule all four sit together at 2.972–2.989. What makes it a class is structural rather than measured — all four are `fp.closureOf` under their own name, from one enumeration (`closureClass`). The rows above therefore name the class instead of repeating a figure, so the four cannot drift apart into an apparent distinction that does not exist. **They share a refusal for the same reason they share a curve**: one capped fixpoint, so all four throw the diameter-and-surface message of *Fixpoint* above at the same ceiling, and a fix applied to one of them would have left three refusing the old way. Re-run: `ci/bench/cost-classes.nix`, arms `transitiveClosure` / `dependents` / `condensationClosure` / `transitiveReduction`.

★ **These figures were re-derived after `condensation` LEFT this class, and they are the re-derived ones.** `condensation` is the partition front door and is an unconditional alias for `fbNode`, the forward–backward arm, which makes no closure call at all; the construction the class describes is published as `condensationClosure`, which used to make TWO closure calls (the graph, and a second over the quotient) and now makes one. The membership claim never depended on the figures — it is structural, `condensationClosure` **is** `fp.closureOf "condensationClosure"`, the one construction its three siblings bind under their own names — but the percentages did, so all four arms were re-run together on one revision of the bench and the paragraph above states that run.

**What that re-run moved was confined to the complete digraph, and every cycle figure came through it unmoved.** The deltas it was recorded with are not restated here: both of their baselines predate the `gen-prelude` dedup bump, so neither side is reproducible from any command at this revision, and a figure binds to a command at a rev rather than to a sentence that once carried it. The paragraph above is the reading that replaced them.

**The asymmetry that re-run exposed survives the bump, but its mechanism does not.** The reason then was an exponent gap between the shapes — the cycle's closure ran at 3.9 and swamped everything downstream of it, where the complete digraph's ran at 3.0 and let the same downstream work show. The bump takes the cycle to ~2.98 against the complete digraph's ~2.96, so **there is no exponent gap left to explain anything**, and what remains is a much smaller difference in sensitivity: `condensationClosure` sits **0.314%** above `transitiveClosure` on the cycle against **0.730%** on the complete digraph, a ratio of 2.3× between the two shapes where the cycle's own margin used to be 0.014%. **A class figure quoted from the cycle is still the more stable number and the less informative one**, but it is no longer nearly blind to work after the closure, and a change to that work is now worth looking for on both shapes. Re-run: `ci/bench/cost-classes.nix`, arms `transitiveClosure` / `condensationClosure`, shapes `cycle` and `complete`, n = 200.

`transitiveReduction` is the one **partial** member, and its carve-out is a property of the **whole graph, not of a node**. Its `closure` is a single binding shared by every node, and the only thing that forces it is the `closureSets.${mid}` lookup sitting behind the `mid != to &&` guard. When *every* node has out-degree ≤ 1 that guard is false everywhere, the shared binding is never forced, and the call measures **linear** — 1,803 allocations at n = 200 on the cycle (exponent 1.00 over n = 50 / 100 / 200), against 25,968,807 for the closure on the same graph. But **one** node with out-degree ≥ 2 anywhere in the graph forces that shared binding, and then the *entire* call pays closure class: on `cyclechord` — the same 200-node ring plus a single chord from `n00000` to `n00100`, so exactly one node has out-degree 2 — it reads **29,413,537**, a factor of **16,314**, landing within **0.0048%** of `transitiveClosure` on that same chorded fixture (29,412,127). ★ The chord is named because *"add one edge"* does not identify a graph and the choice is worth 13.3%: the closure itself goes from 25,968,807 on the ring to 29,412,127 with the chord in, so a figure quoted for an unnamed edge cannot be reproduced or compared. Re-run: `ci/bench/cost-classes.nix`, arm `transitiveReduction`, shapes `cycle` and `cyclechord`.

There is no middle reading — an *average* or *typical* out-degree of 1 buys nothing, so on any realistic dependency graph or host fleet treat `transitiveReduction` as closure class. The carve-out covers exactly those graphs in which every node has at most one successor. In-degree is irrelevant to it, so it holds on in-trees and in-stars as well as on disjoint unions of paths and cycles, and fails on anything denser. Re-run: `ci/bench/cost-classes.nix`, arm `transitiveReduction`, shape `cycle`.

★ These are Nix-heap allocation counters and therefore a **lower bound**, not the bill: `genericClosure` keeps its done-set in C++, so its key comparisons appear on none of the three axes. Read the figures as a floor.

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
| "Can A reach B?" | `canReach` (stops expanding at the target; O(reachable) at bounded out-degree, Θ(n²) on a dense graph — see Performance) | `dependents` (closure class) |
| "What depends on X?" (one target) | `dependentsOf` (reverse index, then O(reachable) at bounded in-degree, Θ(n²) on a dense graph — see Performance) | `dependents` (closure class) |
| "What depends on X, Y, Z?" (multi-target) | `dependents` (closure class, amortized over targets) | `dependentsOf` × 3 (rebuilds index 3×) |
| "Is there a cycle?" | `cycles` (C-level; O(n × reachable) at bounded out-degree, Θ(n²) on a dense graph — see Performance) | `transitiveClosure` (closure class) |
| "Which loop, in order, for a message?" | `cyclePaths` (free on a DAG) | hand-rolled DFS per node (enumerates every simple path even when acyclic) |
| "All paths between A and B" | `pathsBetween` (DFS) | Only for small subgraphs |
| "Full closure for analysis" | `transitiveClosure` | — (use when you genuinely need it) |
| "Minimal graph for diagrams" | `transitiveReduction` | — (closure class unless every node has out-degree ≤ 1) |

### Partitioning for Fleet Scale

For 10,000+ node fleets, partition the graph by environment/datacenter before running global operations:

```nix
# Instead of:
graph.cycles { edges; nodes = ALL_10K_NODES; }  # O(10K × reachable) at bounded out-degree; Θ(n²) dense

# Partition first:
lib.concatMap (partition:
  graph.cycles { inherit edges; nodes = partition; }
) (partitionByEnvironment allNodes)  # 20 × O(500 × reachable) — and 20 × Θ((n/20)³) dense
```

Cross-partition edges are rare in practice. The speed-up is shape-dependent: splitting into `k` partitions divides the `cycles` term by `k` where out-degree is bounded and by `k²` on a complete DAG, so `k = 20` predicts roughly 20× at the bounded end and 400× at the dense end. Those follow from the cost model above rather than from a benchmark — measure your own shape instead of assuming the top of the range.

## Testing

**Two test outputs, and both need running.**

```bash
nix-unit --flake ./ci#tests        # cells asserting a VALUE
nix-unit --flake ./ci#testsError   # cells asserting an ERROR (nix-unit `expectedError`)
nix flake check ./ci               # the batch gate, which covers ./ci#tests
```

**465 tests** across **24 suites** in `./ci#tests` (`arms`, `arrivals`, `boundaries`,
`closure-order`, `edge-maps`, `enumerate`, `fixpoint-tests`, `global`, `hoist`,
`integration`, `labeled-global`, `labeled-transpose`, `order`, `order-front-door`,
`partition`, `prelude-domain`, `preorder`, `purity`, `query`, `regex`, `registry`, `scan`,
`topo`, `traverse`), plus **23** in `./ci#testsError` — run under [nix-unit](https://github.com/nix-community/nix-unit) via
the gen CI harness (`gen.lib.mkCi`). The `purity` suite asserts the library source stays
nixpkgs-lib-free (gen-prelude only).

**Why two outputs.** `checks.default` is a batch asserter that evaluates `expr == expected`
unconditionally over `flake.tests` and nothing else, so a cell with no `expected` and a
throwing `expr` crashes that gate rather than failing a case. Cells whose subject IS the
error therefore live on `flake.testsError` (`ci/tests-error.nix`, outside the `./ci/tests`
tree by construction) — out of the asserter's quantifier and still under nix-unit, which
does read `expectedError`. Both outputs carry a pre-commit hook: `ci` and `ci-error`.

## Theoretical Foundations

The algorithms and design principles draw from:

- **Mokhov (2017)** — *Algebraic Graphs with Class*. *Informed by.* Algebraic graph construction primitives (overlay, connect, vertex, empty) and the compositional approach to graph representation inform gen-graph's edge map operations and structural combinators. Edge map set operations (`unionEdges`, `intersectEdges`, `differenceEdges`) are gen-graph's own contribution built on this algebraic foundation. Mokhov 2017 §4.5 supplies only the equivalence-class *notion* of reduction; `transitiveReduction` is a standard DAG transitive-reduction algorithm (gen-graph's own implementation) and assumes a DAG, since reduction is not unique under cycles. Transpose follows Mokhov 2017 §5.2 *Graph Transpose* directly: the law is that transpose flips the arguments of `connect` and leaves `overlay` unchanged, so direction is reversed rather than erased. `condensation`'s quotient-graph idiom is §4.6 *Preorders and Equivalence Relations* — a condensation is the quotient by the co-SCC equivalence.
- **Arntzenius & Krishnaswami (2016)** — *Datafun: A Functional Datalog*. *Implements.* Monotone fixpoint iteration with convergence guarantees. The `fixpoint` operator enforces monotonicity (edge count must not shrink between iterations), matching Datafun's requirement that fixpoint computations operate over monotone functions on semilattices. Reverse reachability in `dependents`/`dependentsOf` follows the Datafun reverse-query pattern. `directDependents`/`directDependentsOf` expose the underlying reverse-adjacency index directly: the **immediate** reverse neighbours (one edge), in contrast to `dependentsOf`'s **transitive** reverse closure — the distinction matters when a consumer must enumerate only its direct producers' dependents without re-materializing the whole reverse cone.
- **Tarjan (1983)** — *Data Structures and Network Algorithms (RTD)*. *Implements.* Topological rank by longest incoming path. `coneRank` assigns each node `depth = 1 + max(depth of producers)` — the standard topological-rank recurrence — but **restricted to a cone**: only producers inside the supplied node set count, so the rank is computed in O(|cone| + edges-in-cone) via `lib.fix` memoization rather than over the whole graph. Ordering by ascending depth yields a producers-first (reverse-topological) enumeration without building `condensation`. The recurrence is memoized, which makes it linear and also made it a *descent*: forcing the memo map in an unfavourable order walked the cone one evaluator frame per link. The map is therefore forced along a topological order of the cone taken from `topoOrderKahn`, which flattens that descent — the rank recurrence is unchanged, only the order in which its cells are demanded.
- **Neron et al. (2015)** — *A Theory of Name Resolution*. *Implements.* Parent-chain traversal (`ancestorsOf`) follows scope graph P-edge resolution: walking the `parent` partial function upward through scopes corresponds to following P-edges in the resolution calculus (Neron 2015 §2.3). Silent cycle termination chosen over throwing for composability, matching the well-foundedness requirement on the parent relation.
- **Kahn, A. B. (1962)** — *Topological sorting of large networks*, CACM 5(11). *Implemented.* **`topoOrderKahn`** is Kahn's algorithm and `topoOrder` is the door that selects it (see Ordering): an indegree count over the dependency relation, a ready set of indegree-zero nodes, decrement-on-emit restricted to the pick's successors, and the residual-emptiness check that detects a cycle. Incomparable nodes are emitted in ascending key order, which is what makes the result a function of the node set rather than of the input permutation. This is A. B. Kahn 1962 and **not** Gilles Kahn 1974 below — a different author and a different result, a conflation this codebase has made before. Min-extraction over the ready set is the one place the algorithm is not linear, and the ready set is a **leftist heap** (see Crane 1972 / Okasaki 1998 below) — O(log m) insert and delete-min, so the loop attains the Ω(m log m) comparison bound that emitting in min-key order under a caller-supplied comparator inherits. ★ This entry previously recorded that a priority queue was out of reach because pure Nix has no mutable heap. That is false: persistent priority queues need no mutation. The same claim is still what `condensationClosure` gives for not being Tarjan's algorithm, and **that** justification is now unsupported rather than re-derived. The cycle report is deliberately **not** read off the Kahn residual, which knows only that nodes went unemitted and not which cycles they form; it comes from `cycles` and a partition arm (`fbNode`, bound by name), so the failure path pays both — and neither may be quoted as the cost alone, since which of the two is larger flips with the graph's shape and with the allocation axis measured — while the success path pays neither.
- **Crane (1972)** — *Linear Lists and Priority Queues as Balanced Binary Trees*; **Knuth, *TAOCP* vol. 3 §5.2.3**. *Implements.* `topoOrder`'s ready set is a leftist heap: `null | { k; l; r; rank; }`, `rank` the right-spine length, with the leftist invariant `rank l >= rank r` at every node. Merge walks and rebuilds the two right spines, which the invariant keeps at O(log m), and insert and delete-min are both defined as a merge. Immutability is paid in **path copying** rather than in asymptotics — no node is overwritten, so a merge allocates one attrset per node on the spine it rebuilds, giving Θ(n log n) attrsets over the loop. That is an achieved upper bound, not a proven optimum: the comparison-sorting bound rules out a Θ(n) *comparison-based ordering*, but it does not prove Θ(n log n) *allocations* necessary.
- **Okasaki (1998)** — *Purely Functional Data Structures*, §3.1. *Informed by.* The book's subject is exactly this substrate restriction: priority queues with O(log n) worst-case merge and delete-min and no mutable store. Leftist heaps are §3.1; skew heaps (Sleator & Tarjan 1986) and pairing heaps (Fredman, Sedgewick, Sleator & Tarjan 1986) are alternatives with the same property. Cited here because "pure Nix cannot express a priority queue" was written into this library as a justification for a quadratic, and it is a false impossibility claim.
- **Kahn (1974)** — *The Semantics of a Simple Language for Parallel Programming*. *Informed by.* Continuous functions over streams with deterministic dataflow semantics. gen-graph's lazy accessor pattern — traversal only forces nodes it visits — aligns conceptually with Kahn's model where computing stations produce output incrementally as input arrives, and monotonicity ensures that receiving more input can only provoke more output (Kahn 1974 §2.2.4). The pre-order combinators (`preorder.nix`) make this demand property load-bearing: `expandPreorder`'s `edges` read the *resolved* payload, so a node's successors are demand-generated, and a `seen0`-pruned frame is never forced.
- **Tarjan (1972)** — *Depth-First Search and Linear Graph Algorithms*. *Implements.* Beyond the SCC/condensation use, the pre-order traversal combinators (`foldPreorder`, `expandPreorder`, `foldReach`) fold in DFS pre-order — a frame before its children, siblings in list order, each frame visited once via a first-occurrence visited set. First-occurrence is Tarjan's pre-order discovery numbering; `genericClosure` (BFS, single-keyed, payload-blind) structurally cannot express the order, payload or edge exposure these carry.
- **Meijer, Fokkinga & Paterson (1991)** — *Functional Programming with Bananas, Lenses, Envelopes and Barbed Wire*. *Informed by.* `foldPreorder` has the shape of a hylomorphism: the visited-set coalgebra unfolds the (possibly cyclic) graph into its finite DFS spanning forest, which `expand` folds (catamorphism) into the accumulator. `expandPreorder` and `foldReach` specialize that accumulator to an ordered witness list — an ordered, payload-carrying fold rather than a set-returning closure.
- **Brzozowski (1964)** — *Derivatives of Regular Expressions*. *Implements.* The labeled-query `follow` kernel steps a Brzozowski derivative of the label regex alongside the graph walk; `deriv l r` and `nullable r` are the classical derivative and nullability functions, so a path's label word is accepted iff folding `deriv` over it lands in a nullable state. **The termination guarantee is also his**: Theorem 5.2 — "every regular expression has only a finite number of dissimilar derivatives" — where the similarity of Definition 5.2 is the ACI identities of *alternation only* (`R+R=R`, `P+Q=Q+P`, `(P+Q)+R=P+(Q+R)`). That is what bounds the state set and makes the canonical `stateKey` a sound seen-set key, so the `all` mode's (node × derivative-state) product automaton terminates on cyclic graphs. The bound holds *modulo* those identities, which means the normalization has to be performed rather than merely be available — Brzozowski's own proof (Appendix II) names `R+R=R` as the identity that terminates the process.
- **Owens, Reppy & Turon (2009)** — *Regular-expression Derivatives Re-examined*. *Implements — the enlarged normalization, not the finiteness theorem.* Definition 4.1 is a strict superset of Brzozowski's similarity: on top of the ACI identities of alternation it adds sequence flattening with unit/zero absorption and star collapse, and it supplies the smart-constructor strategy this library follows, normalizing on the way in rather than canonicalizing after the fact. Owens, Reppy & Turon credit the finiteness result to Brzozowski themselves (§3.3, §4.1) and state no termination theorem for the enlarged rule set; relying on the composite is folklore, and safe in this direction, because every added identity is semantics-preserving and size-decreasing and so can only merge states that ACI alone would have kept apart. §4.2's character-set merge (`alt` of `any` with a literal) is **not** implemented — a minimality rule, never a termination one.
- **Néron, Tolmach, Visser & Wachsmuth (2015)** — *A Theory of Name Resolution*. *Implements.* Beyond parent-chain resolution (above), the labeled query surface generalizes scope-graph reachability to arbitrary edge labels: `query`'s `follow` is a reachability regex over labels, and the `visible`/`layers` specificity order generalizes Néron's D < I < P label order.
- **Apt, Blair & Walker (1988)** — *Towards a Theory of Declarative Knowledge*, Lemma 1. *Implements — the graph half only.* The lemma is a biconditional between a program property and a graph property: no cycle of the dependency graph contains a negative edge. `cyclicEdgesWhere` computes that graph property for a caller-supplied notion of "negative", and the construction is the paper's **own** proof method for the converse — decompose the dependency graph into strongly connected components (which is `condensation`), then read the retained labelled edges against that partition. gen-graph has no programs, no relation symbols and no clauses, and does not know which labels are negative, so it computes the graph side and names it accordingly; the program-level word belongs to a caller that has programs. The archived text carries an OCR hazard inside the converse half of that proof (a flattened inequality), so its *prose* is cited and no inequality from it is lifted into code, comment or oracle — the stratum-index arithmetic plays no part here, only the decomposition.
- **van Antwerpen, Poulsen, Rouvoet & Visser (2018)** — *Scopes as Types*. *Implements.* The per-query label order carries an end-of-path token: `order.endOfPath` competes against a word's next label rank at exhaustion, so stopping can out- or under-rank continuation (default `-1` = prefix-wins), matching van Antwerpen's per-query ≤ with an end-of-path marker.
