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
condensation       : { edges, nodes, ... } → { reps, bottomUp, members, sccs, sccOf, condEdges }
coneRank           : { edges, ... } → [id] → { order, depth }
directDependents   : { edges, nodes, ... } → { id → [id] }
directDependentsOf : { edges, nodes, ... } → id → [id]
```

**`cycles g`** — nodes that appear in any cycle (self-reachable). Uses C-level BFS per node via `selfReachable` — no full transitive closure materialization needed. Returns a sorted list.

```nix
graph.cycles g   # → [] for a DAG, → [ "a" "b" "c" ] for a → b → c → a
```

**`cyclePaths g`** — one representative simple cycle per cyclic component, as an **ordered** node list rotated to begin at the component's smallest key. `[]` for a DAG. Where `cycles` answers *which nodes lie on a cycle* (a key-sorted membership set), `cyclePaths` answers *what the loop is*: every consecutive pair in a returned list is a real edge, so a caller may join it with `->` and state something true. Reach for it whenever the cycle is going to be **shown to a human**.

One per component, not all: the SCC is the canonical object, the cycle through it is existential. Enumerating every simple cycle is Johnson 1975 and is deliberately not provided.

Cost is asymmetric by design. `cycles` short-circuits a DAG before any path work, so the acyclic case — the ordinary one — pays the self-reachability pass and nothing more. That pass *is* `cycles`, so it inherits `cycles`' shape dependence: O(n × reachable) where out-degree is bounded, but Θ(n³) on a complete DAG (see Performance). `condensation` and `pathsBetween` run only once the graph is known cyclic, i.e. only on the branch a caller refuses on.

```nix
# b → d → c → b, keys sorting b < c < d
graph.cycles g       # → [ "b" "c" "d" ]   membership, key-sorted
graph.cyclePaths g   # → [ [ "b" "d" "c" ] ]   the traversal — b→d, d→c, c→b
```

**`dependents g targetId`** — all nodes that transitively reach `targetId` (reverse reachability). Uses full transitive closure + transpose — closure-class cost (super-quadratic, see Performance), O(1) lookup thereafter. Best for multi-target queries (amortized).

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

**`condensation g`** — collapses each SCC to a super-node and returns the condensation (quotient) graph. Closure-based, so it carries the closure-class cost: super-quadratic rather than the O(n²) once documented here (see Performance). Not Tarjan's linear single-DFS, whose mutable stack is out of reach in pure Nix. Returns a record:

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

**`coneRank g cone`** — producers-first topological rank of a node set, computed **cone-locally**. Returns `{ order; depth; }` where `depth id = 0` if `id` has no producer inside `cone`, else `1 + max(depth of its in-cone producers)`, and `order` is `cone` sorted ascending by depth with an id tie-break (so every producer precedes its consumers). Memoized via `lib.fix` over the cone, so it runs in O(|cone| + edges-in-cone) — it does **not** materialize the whole-graph `condensation`. The cone must be acyclic (every producer is strictly shallower than its consumer). This is RTD 1983 topological rank restricted to a dependent cone.

```nix
graph.coneRank g [ "A" "B" "X" ]    # for B→A, X→B
# → { order = [ "A" "B" "X" ]; depth = { A = 0; B = 1; X = 2; }; }
```

**`directDependents g`** — the full **direct** reverse-adjacency map `{ id → [direct dependents of id] }`: the immediate reverse neighbours of every node, in one O(E) `groupBy`. This is the public face of the internal `_reverseIndex`. **Direct**, in contrast to `dependentsOf`'s **transitive** closure — a producer with no consumer simply has no key.

**`directDependentsOf g id`** — the immediate dependents of a single node: `(directDependents g).${id} or [ ]`.

```nix
graph.directDependentsOf g "A"   # → [ "B" ]      (DIRECT — immediate neighbour)
graph.dependentsOf       g "A"   # → [ "B" "X" ]  (TRANSITIVE — full reverse cone)
```

### Ordering

`topoOrder` is **the** ordering front door for the gen ecosystem — Kahn's algorithm
(A. B. Kahn 1962; not Gilles Kahn 1974, which `preorder.nix` cites for something else)
over an accessor. `entry*`/`phaseOrder` are the home-manager-style authoring layer on top
of it, for consumers that would rather write `before`/`after` constraints than build an
accessor.

```
topoOrder { nodes; edges; keyOf ? id; lessThan ? builtins.lessThan }
    : { ok = true; order = [ node ]; } | { ok = false; cycles = [ [ node ] ]; }

entryAnywhere            : entry                       ( {} — no constraints )
entryAfter  [ "a" ]      : entry                       ( comes after "a" )
entryBefore [ "b" ]      : entry                       ( comes before "b" )
entryBetween befs afts   : entry
phaseOrder  { name = entry; ... } : [ name ]           ( forward topological order )
```

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
`topoOrder` and `phaseOrder`. **Cost is the only remaining bound**: allocation grows
quadratically in `n` (measured exponent 2.00 on `list.elements`, chain and wide), so a large
graph gets slow rather than refused.

**What pays that quadratic is now two accumulators, not three.** The loop carries the
emitted list, which allocates a fresh `k`-element vector at step `k`, and the indegree map,
which is copied whole per step; both are Θ(n²). The **ready set is not among them**: it is a
leftist heap with O(log m) insert and delete-min, so it costs Θ(n log n). Holding it as a
sorted array instead — rebuilding the unconsumed residue and re-sorting it on every arrival —
was a third, independent quadratic, and on shapes with out-degree it was the largest single
term: 60% of the loop's `list.elements` on independent pairs, 21% on a fleet of ten-chains,
43% on a binary tree, and 0% on a chain, whose ready set never holds two nodes at once. The
trade is stated rather than netted: the heap **adds** to `sets.elements`, one attrset per
node on each merge path, measured at 63 → 89 attrsets per node across n = 1000 → 8000 — a
Θ(n log n) term, today dominated by the indegree map's Θ(n²) and the leading set-axis cost
once that is fixed.

Re-run, and the two halves have **different producers**. Every figure in the paragraph above
is a comparison between **two revisions of this library**, and the array ready set exists at
neither the tip nor in any arm of `ci/bench/cost-classes.nix` — so no command in this
repository produces a share or a delta, and none can. Those come from the committed
two-revision harness: `den-architecture`,
`specs/2026-08-08-gen-graph-ready-set-quadratic.r1-*`, whose `.r1-data-note.md` carries the
procedure, the pinned revisions and the md5 anchors. **Post-change** cells — what the shipped
`topoOrder` costs on any shape, as it stands — come from `ci/bench/cost-classes.nix`, arm
`topoOrder`, shapes `wide` / `fleet` / `discrim` / `deepwide`. ★ Before quoting a
`sets.elements` figure from that bench, read `ci/bench/sentinel.sh`: `sets` figures are
comparable only within one revision of the bench file, and the sentinel is what says which
revision you are on.

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
labeledFixtures : { world, cyclic, poisoned }   # { labeledEdges; } records for labeled queries
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

### Labeled Queries

The label-blind surface above (`edges : id → [id]`) is untouched; labeled queries are a
strictly additive layer for graphs whose edges carry a **kind**. A labeled graph exposes one
extra accessor:

```
labeledEdges : id → [ { label; target; } ]
```

Reachability is then constrained by a **regex over labels** — a query answers a node iff the
word spelled by the labels along some path from `from` matches the `follow` expression.

**`labeledFrom`** adapts one plain accessor per edge kind into the labeled contract:

```nix
g = graph.labeledFrom {
  contains = id: containsEdges id;   # each returns a plain [ id ] list
  member   = id: memberEdges id;
};
```

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

**gen-scope adapter recipe** (recipe only — gen-graph does **not** import gen-scope):

```nix
# consumer code: wrap gen-scope's per-label followEdge into the labeled contract
g = graph.labeledFrom {
  imports = id: scope.followEdge "imports" self id;
  parent  = id: scope.followEdge "parent" self id;
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
| `reachableFrom` | O(reachable) | C-level BFS via `builtins.genericClosure` |
| `reachableWhere` | O(reachable) | same C-level BFS, filter applied after |
| `canReach` | O(reachable from source) | C-level BFS, stops exploring from target |
| `selfReachable` | O(reachable from node) | C-level BFS checking self-reappearance |
| `ancestorsOf` | O(depth) | single-path walk |
| `pathsBetween` | O(paths × depth) | exponential in path count; use on small subgraphs |
| `materialize` | O(nodes × avg degree) | one-time scan |
| `transitiveClosure` | **closure class** (see below) | fixpoint over materialized map |
| `transitiveReduction` | **closure class** unless *every* node has out-degree ≤ 1 (see below) | needs full closure; O(1) membership via attrsets |
| `cycles` | `Θ(Σ_v Σ_{u ∈ reach v} (1 + outdeg u))` — i.e. O(nodes × reachable) only where out-degree is **bounded**; Θ(n³) on a complete DAG | per-node C-level BFS (no full closure needed). The per-visit cost is O(1 + outdeg), not O(1), because `selfReachable`'s `genericClosure` operator re-reads `edges` at every visit |
| `cyclePaths` | on a DAG, exactly the `cycles` cost above — so Θ(n³) on a complete DAG, **not** O(nodes × reachable); + condensation (super-quadratic, see its own row) and simple-path search once cyclic | short-circuits before any path work when acyclic |
| `dependents` | **closure class** (see below) | full transitive closure + transpose |
| `dependentsOf` | O(nodes + reachable) | reverse index + C-level BFS |
| `dependentsFrontier` | O(nodes + reachable) | reverse index + level-by-level BFS, pruned early |
| `coScc` | O(reachable from u, v) | two `canReach` probes, no full closure |
| `condensation` | **closure class** (see below) | two transitive closures (graph + quotient) |
| `coneRank` | O(|cone| + edges-in-cone) | `lib.fix` memoized depth, cone-local (no condensation) |
| `topoOrder` / `phaseOrder` | O(n + E) decrements, but **quadratic in allocation** — exponent 2.00 on `list.elements`, chain and wide | **two** accumulators pay it: the emitted list and the indegree map. The ready set does not — it is a leftist heap, Θ(n log n), where a re-sorted array was a third quadratic worth 60% of the `wide` list allocation. The heap's price is on `sets.elements`, 63 → 89 attrsets per node over n = 1000 → 8000. No frame ceiling — the loop is a bounded iteration, so no node count aborts or is refused |
| `directDependents` / `directDependentsOf` | O(edges) | one `groupBy` reverse-adjacency map |
| `seededFixpoint` | O(work per delta) | semi-naive: each iteration touches only the frontier |
| `roots` / `leaves` | O(nodes × avg degree) | single scan of all edges |
| `select` | O(nodes) | one pass over node list |
| `unionEdges` / `intersectEdges` / `differenceEdges` | O(edges) | attrset membership O(1) per edge |

**The closure class.** `transitiveClosure`, `dependents`, `condensation` and `transitiveReduction` each cost one `fp.transitiveClosure` call, and on **`list.elements`** they measure as **one curve**, not four costs. The class is stated on that axis because it dominates the bill: at n = 200 it exceeds the other two counters combined by 418× on the complete digraph and 124× on the cycle. On a complete digraph the growth **exponent** is ~3.0 for all four and the exponents agree to 0.21% (2.980–2.986); the **raw** figures agree that closely only for the first three (0.332% apart at n = 200), while `transitiveReduction` sits 11.6% above `transitiveClosure` — the 0.21% is a statement about exponents, not about allocation counts. `transitiveClosure` alone is 99.7% of `dependents`. On a simple cycle the first three are ~3.9, and their spread **narrows** with n — 0.294% at n = 50, 0.081% at n = 100, 0.021% at n = 200 — so the class claim strengthens as the graph grows rather than holding at one fixed bound. It is **super-quadratic on both shapes — not the O(nodes²) once documented here.** This is practical scaling guidance on the dominant axis, not an identity on every axis: on `sets.elements` the complete-digraph exponents separate, `transitiveClosure` at 0.76 against 1.93–1.99 for its siblings. What makes it a class is structural rather than measured — all four literally call `fp.transitiveClosure`. The rows above therefore name the class instead of repeating a figure, so the four cannot drift apart into an apparent distinction that does not exist. Re-run: `ci/bench/cost-classes.nix`, arms `transitiveClosure` / `dependents` / `condensation` / `transitiveReduction`.

`transitiveReduction` is the one **partial** member, and its carve-out is a property of the **whole graph, not of a node**. Its `closure` is a single binding shared by every node, and the only thing that forces it is the `closureSets.${mid}` lookup sitting behind the `mid != to &&` guard. When *every* node has out-degree ≤ 1 that guard is false everywhere, the shared binding is never forced, and the call measures **linear** — 1,803 allocations at n = 200 on the cycle, against 565,640,803 for the closure. But **one** node with out-degree ≥ 2 anywhere in the graph forces that shared binding, and then the *entire* call pays closure class: adding a single edge to the n = 200 cycle takes it from 1,803 to 571,115,707, a factor of **316,759**, landing within 0.001% of the full closure on the same fixture.

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
| "Can A reach B?" | `canReach` (O(reachable)) | `dependents` (closure class) |
| "What depends on X?" (one target) | `dependentsOf` (O(n + reachable)) | `dependents` (closure class) |
| "What depends on X, Y, Z?" (multi-target) | `dependents` (closure class, amortized over targets) | `dependentsOf` × 3 (rebuilds index 3×) |
| "Is there a cycle?" | `cycles` (C-level; O(n × reachable) at bounded out-degree, Θ(n³) on a dense graph — see Performance) | `transitiveClosure` (closure class) |
| "Which loop, in order, for a message?" | `cyclePaths` (free on a DAG) | hand-rolled DFS per node (enumerates every simple path even when acyclic) |
| "All paths between A and B" | `pathsBetween` (DFS) | Only for small subgraphs |
| "Full closure for analysis" | `transitiveClosure` | — (use when you genuinely need it) |
| "Minimal graph for diagrams" | `transitiveReduction` | — (closure class unless every node has out-degree ≤ 1) |

### Partitioning for Fleet Scale

For 10,000+ node fleets, partition the graph by environment/datacenter before running global operations:

```nix
# Instead of:
graph.cycles { edges; nodes = ALL_10K_NODES; }  # O(10K × reachable) at bounded out-degree; Θ(n³) dense

# Partition first:
lib.concatMap (partition:
  graph.cycles { inherit edges; nodes = partition; }
) (partitionByEnvironment allNodes)  # 20 × O(500 × reachable) — and 20 × Θ((n/20)³) dense
```

Cross-partition edges are rare in practice. The speed-up is shape-dependent: splitting into `k` partitions divides the `cycles` term by `k` where out-degree is bounded and by `k²` on a complete DAG, so `k = 20` predicts roughly 20× at the bounded end and 400× at the dense end. Those follow from the cost model above rather than from a benchmark — measure your own shape instead of assuming the top of the range.

## Testing

```bash
nix flake check --override-input gen-graph . ./ci        # all suites
nix flake check --override-input gen-graph . ./ci 2>&1   # with test output
```

**232 tests** across **13 suites** (`edge-maps`, `enumerate`, `fixpoint`, `global`,
`integration`, `order`, `preorder`, `purity`, `query`, `regex`, `registry`, `topo`, `traverse`), run under
[nix-unit](https://github.com/nix-community/nix-unit) via the gen CI harness
(`gen.lib.mkCi`). The `purity` suite asserts the library source stays nixpkgs-lib-free
(gen-prelude only).

## Theoretical Foundations

The algorithms and design principles draw from:

- **Mokhov (2017)** — *Algebraic Graphs with Class*. *Informed by.* Algebraic graph construction primitives (overlay, connect, vertex, empty) and the compositional approach to graph representation inform gen-graph's edge map operations and structural combinators. Edge map set operations (`unionEdges`, `intersectEdges`, `differenceEdges`) are gen-graph's own contribution built on this algebraic foundation. Mokhov 2017 §4.5 supplies only the equivalence-class *notion* of reduction; `transitiveReduction` is a standard DAG transitive-reduction algorithm (gen-graph's own implementation) and assumes a DAG, since reduction is not unique under cycles. Transpose follows Mokhov 2017 §5.2 *Graph Transpose* directly: the law is that transpose flips the arguments of `connect` and leaves `overlay` unchanged, so direction is reversed rather than erased. `condensation`'s quotient-graph idiom is §4.6 *Preorders and Equivalence Relations* — a condensation is the quotient by the co-SCC equivalence.
- **Arntzenius & Krishnaswami (2016)** — *Datafun: A Functional Datalog*. *Implements.* Monotone fixpoint iteration with convergence guarantees. The `fixpoint` operator enforces monotonicity (edge count must not shrink between iterations), matching Datafun's requirement that fixpoint computations operate over monotone functions on semilattices. Reverse reachability in `dependents`/`dependentsOf` follows the Datafun reverse-query pattern. `directDependents`/`directDependentsOf` expose the underlying reverse-adjacency index directly: the **immediate** reverse neighbours (one edge), in contrast to `dependentsOf`'s **transitive** reverse closure — the distinction matters when a consumer must enumerate only its direct producers' dependents without re-materializing the whole reverse cone.
- **Tarjan (1983)** — *Data Structures and Network Algorithms (RTD)*. *Implements.* Topological rank by longest incoming path. `coneRank` assigns each node `depth = 1 + max(depth of producers)` — the standard topological-rank recurrence — but **restricted to a cone**: only producers inside the supplied node set count, so the rank is computed in O(|cone| + edges-in-cone) via `lib.fix` memoization rather than over the whole graph. Ordering by ascending depth yields a producers-first (reverse-topological) enumeration without building `condensation`.
- **Neron et al. (2015)** — *A Theory of Name Resolution*. *Implements.* Parent-chain traversal (`ancestorsOf`) follows scope graph P-edge resolution: walking the `parent` partial function upward through scopes corresponds to following P-edges in the resolution calculus (Neron 2015 §2.3). Silent cycle termination chosen over throwing for composability, matching the well-foundedness requirement on the parent relation.
- **Kahn, A. B. (1962)** — *Topological sorting of large networks*, CACM 5(11). *Implemented.* `topoOrder` is Kahn's algorithm: an indegree count over the dependency relation, a ready set of indegree-zero nodes, decrement-on-emit restricted to the pick's successors, and the residual-emptiness check that detects a cycle. Incomparable nodes are emitted in ascending key order, which is what makes the result a function of the node set rather than of the input permutation. This is A. B. Kahn 1962 and **not** Gilles Kahn 1974 below — a different author and a different result, a conflation this codebase has made before. Min-extraction over the ready set is the one place the algorithm is not linear, and the ready set is a **leftist heap** (see Crane 1972 / Okasaki 1998 below) — O(log m) insert and delete-min, so the loop attains the Ω(m log m) comparison bound that emitting in min-key order under a caller-supplied comparator inherits. ★ This entry previously recorded that a priority queue was out of reach because pure Nix has no mutable heap. That is false: persistent priority queues need no mutation. The same claim is still what `condensation` gives for not being Tarjan's algorithm, and **that** justification is now unsupported rather than re-derived. The cycle report is deliberately **not** read off the Kahn residual, which knows only that nodes went unemitted and not which cycles they form; it comes from `cycles`/`condensation`, so the failure path pays both — and neither may be quoted as the cost alone, since which of the two is larger flips with the graph's shape and with the allocation axis measured — while the success path pays neither.
- **Crane (1972)** — *Linear Lists and Priority Queues as Balanced Binary Trees*; **Knuth, *TAOCP* vol. 3 §5.2.3**. *Implements.* `topoOrder`'s ready set is a leftist heap: `null | { k; l; r; rank; }`, `rank` the right-spine length, with the leftist invariant `rank l >= rank r` at every node. Merge walks and rebuilds the two right spines, which the invariant keeps at O(log m), and insert and delete-min are both defined as a merge. Immutability is paid in **path copying** rather than in asymptotics — no node is overwritten, so a merge allocates one attrset per node on the spine it rebuilds, giving Θ(n log n) attrsets over the loop. That is an achieved upper bound, not a proven optimum: the comparison-sorting bound rules out a Θ(n) *comparison-based ordering*, but it does not prove Θ(n log n) *allocations* necessary.
- **Okasaki (1998)** — *Purely Functional Data Structures*, §3.1. *Informed by.* The book's subject is exactly this substrate restriction: priority queues with O(log n) worst-case merge and delete-min and no mutable store. Leftist heaps are §3.1; skew heaps (Sleator & Tarjan 1986) and pairing heaps (Fredman, Sedgewick, Sleator & Tarjan 1986) are alternatives with the same property. Cited here because "pure Nix cannot express a priority queue" was written into this library as a justification for a quadratic, and it is a false impossibility claim.
- **Kahn (1974)** — *The Semantics of a Simple Language for Parallel Programming*. *Informed by.* Continuous functions over streams with deterministic dataflow semantics. gen-graph's lazy accessor pattern — traversal only forces nodes it visits — aligns conceptually with Kahn's model where computing stations produce output incrementally as input arrives, and monotonicity ensures that receiving more input can only provoke more output (Kahn 1974 §2.2.4). The pre-order combinators (`preorder.nix`) make this demand property load-bearing: `expandPreorder`'s `edges` read the *resolved* payload, so a node's successors are demand-generated, and a `seen0`-pruned frame is never forced.
- **Tarjan (1972)** — *Depth-First Search and Linear Graph Algorithms*. *Implements.* Beyond the SCC/condensation use, the pre-order traversal combinators (`foldPreorder`, `expandPreorder`, `foldReach`) fold in DFS pre-order — a frame before its children, siblings in list order, each frame visited once via a first-occurrence visited set. First-occurrence is Tarjan's pre-order discovery numbering; `genericClosure` (BFS, single-keyed, payload-blind) structurally cannot express the order, payload or edge exposure these carry.
- **Meijer, Fokkinga & Paterson (1991)** — *Functional Programming with Bananas, Lenses, Envelopes and Barbed Wire*. *Informed by.* `foldPreorder` has the shape of a hylomorphism: the visited-set coalgebra unfolds the (possibly cyclic) graph into its finite DFS spanning forest, which `expand` folds (catamorphism) into the accumulator. `expandPreorder` and `foldReach` specialize that accumulator to an ordered witness list — an ordered, payload-carrying fold rather than a set-returning closure.
- **Brzozowski (1964)** — *Derivatives of Regular Expressions*. *Implements.* The labeled-query `follow` kernel steps a Brzozowski derivative of the label regex alongside the graph walk; `deriv l r` and `nullable r` are the classical derivative and nullability functions, so a path's label word is accepted iff folding `deriv` over it lands in a nullable state.
- **Owens, Reppy & Turon (2009)** — *Regular-expression Derivatives Re-examined*. *Implements.* Derivative states are kept in an ACI-normal form (alternation flattened/sorted/deduplicated, sequence flattened with unit/zero absorption, star collapsed), so the derivative set of any expression is finite and the canonical `stateKey` is a sound seen-set key — this is what makes the `all` mode's (node × derivative-state) product automaton terminate on cyclic graphs.
- **Néron, Tolmach, Visser & Wachsmuth (2015)** — *A Theory of Name Resolution*. *Implements.* Beyond parent-chain resolution (above), the labeled query surface generalizes scope-graph reachability to arbitrary edge labels: `query`'s `follow` is a reachability regex over labels, and the `visible`/`layers` specificity order generalizes Néron's D < I < P label order.
- **van Antwerpen, Poulsen, Rouvoet & Visser (2018)** — *Scopes as Types*. *Implements.* The per-query label order carries an end-of-path token: `order.endOfPath` competes against a word's next label rank at exhaustion, so stopping can out- or under-rank continuation (default `-1` = prefix-wins), matching van Antwerpen's per-query ≤ with an end-of-path marker.
