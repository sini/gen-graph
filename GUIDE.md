# ABC on Graph Queries

gen-graph's small guide into accessor-based graph queries and the research behind them.

Fear not, this guide does not require reading academic papers or knowing graph theory. We reference the papers so *you* know where to look if you're curious, but everything here is explained from first principles.

The purpose of this guide is to show that **you already work with graphs in Nix** and that **gen-graph just gives you the vocabulary to ask questions about them**.

> From a user perspective, you define your data however you want. gen-graph never touches it. This guide is here to help you understand what questions you can ask and why the API looks the way it does.

## You already have a graph

Suppose you have a set of NixOS services:

```nix
services = {
  web    = { deps = [ "api" ];         type = "frontend"; };
  api    = { deps = [ "db" "cache" ];  type = "backend";  };
  worker = { deps = [ "db" "queue" ];  type = "backend";  };
  db     = { deps = [];                type = "datastore"; };
  cache  = { deps = [];                type = "datastore"; };
  queue  = { deps = [];                type = "datastore"; };
};
```

That's a graph. Each service is a **node**. Each entry in `deps` is an **edge** pointing from one node to another. You just can't ask it any questions yet.

## The accessor pattern: teach gen-graph to read your data

gen-graph doesn't know what shape your data takes. It doesn't care. You teach it by providing **accessor functions** — tiny functions that answer "what are the edges from this node?" and "what nodes exist?"

```nix
g = {
  edges = id: (services.${id} or { deps = []; }).deps;
  nodes = builtins.attrNames services;
};
```

That's it. Two functions. Now gen-graph can answer any structural question about your services:

```nix
graph.reachableFrom g "web"     # [ "api" "cache" "db" ]
graph.roots g                   # [ "web" "worker" ]
graph.leaves g                  # [ "cache" "db" "queue" ]
graph.cycles g                  # []  — it's a DAG
graph.dependents g "db"         # [ "api" "web" "worker" ]
```

> **Why functions instead of a fixed format?** Because your data already exists. You shouldn't have to reshape it into gen-graph's preferred structure. The accessor pattern means gen-graph works with *any* attrset, database, or computed value — as long as you can write a function that answers "edges from id" and "list of ids."

This design comes from Radul's *Art of the Propagator* (2009) — the idea that computations should compose via function arguments rather than shared state. Your accessor functions are the interface contract; gen-graph is the query engine.

## Two kinds of edges: I-edges and P-edges

In the world of programming language semantics, Néron et al. (2015) introduced **scope graphs** — a model for how names resolve in programs. They identified two fundamental edge types:

| Edge | Name | Direction | Meaning |
|------|------|-----------|---------|
| **I** | Import | Forward/outward | "I depend on that" / "I import that" |
| **P** | Parent | Upward/lexical | "I'm contained within that" |

In gen-graph's API, these map to the two accessor functions:

- **`edges`** = I-edges. "Follow my dependencies." These go *outward* — from a service to its requirements, from a module to its imports, from a scope to what it references.

- **`parent`** = P-edges. "Who contains me?" These go *upward* — from a child scope to its enclosing scope, from a user to their host, from a nested module to its parent.

```nix
# I-edges: which services does "api" import/depend on?
g.edges "api"       # [ "db" "cache" ]

# P-edge: what contains "grandchild"?
g.parent "grandchild"   # "child1"
```

### Why two edge types matter

The distinction isn't arbitrary formalism. It captures a fundamental asymmetry in how composition works:

**I-edges are many-to-many.** A service can depend on many others. Many services can depend on the same one. Import graphs are DAGs (or occasionally cyclic).

**P-edges form a tree.** Every node has at most one parent. The parent chain always terminates (at a root). You can't be contained in two places at once.

This means the algorithms are different:

- `reachableFrom` follows I-edges via BFS — multiple branches, cycle detection needed
- `ancestorsOf` follows P-edges linearly — single chain, always terminates (with cycle protection just in case)

In den's configuration system, I-edges are `includes` (one aspect imports another) and P-edges are the entity hierarchy (a user lives inside a host). gen-graph provides the vocabulary to query both.

## Lazy traversal: only visit what you need

Here's something subtle about gen-graph's design: traversal functions **never look at `nodes`**.

```nix
# These only use `edges`:
graph.reachableFrom g "web"        # follows edges from "web" outward
graph.pathsBetween g "web" "db"    # DFS from "web" toward "db"
graph.ancestorsOf g "grandchild"   # follows parent links upward
```

If your graph has 10,000 nodes but only 5 are reachable from `"web"`, gen-graph only evaluates those 5. The other 9,995 are never touched.

This comes from Kahn (1974) — *demand-driven evaluation*. In Nix, where every value is lazy, this is natural: the accessor function `edges "web"` is only called when gen-graph actually visits `"web"`. If a node is unreachable, its accessor is never invoked.

> **Rule of thumb:** Use traversal functions (`reachableFrom`, `ancestorsOf`, `pathsBetween`) when you're exploring from a starting point. Use global functions (`cycles`, `dependents`, `roots`) when you need the full picture.

## Point queries: asking yes/no questions

Sometimes you don't need a list of nodes — just a yes or no:

```nix
graph.canReach g "web" "db"      # true — web reaches db transitively
graph.canReach g "db" "web"      # false — db has no outgoing edges
graph.selfReachable g "a"        # true (if a→b→c→a cycle exists)
```

**`canReach`** answers "is there any path from A to B?" It uses C-level BFS internally — the same `builtins.genericClosure` that powers `reachableFrom`. It visits nodes starting from the source until it finds the target (or exhausts reachable nodes).

**`selfReachable`** answers "is this node in a cycle?" It checks whether the node appears in its own reachable set — i.e., whether following edges from it eventually leads back to it. This is the building block for `cycles`.

Both are lazy in the same way as `reachableFrom` — they never enumerate `nodes`, only follow edges from the start point.

## Impact analysis: who depends on what?

"If I change the database, what breaks?" This is **reverse reachability** — finding everything upstream that depends on a target.

gen-graph offers two variants:

```nix
# Single target (efficient — O(n + reachable)):
graph.dependentsOf g "db"     # [ "api" "web" "worker" ]

# Multi-target (amortized — full closure computed once):
graph.dependents g "db"       # same result, different algorithm
```

**`dependentsOf`** builds a reverse edge index once (O(n)), then does C-level BFS from the target in the reversed graph. Fast for one-off queries.

**`dependents`** computes the full transitive closure, transposes it, then looks up the target. Expensive upfront (O(n²)), but if you're querying multiple targets, the closure is computed once and each lookup is O(1).

**`impactOf`** is an alias for `dependentsOf` — the efficient single-target variant. "What's the impact of changing X?"

```nix
# "What breaks if we remove the cache layer?"
graph.impactOf g "cache"   # [ "api" "web" ]
```

## Global analysis: when you need everything

Some questions genuinely require examining the entire graph:

- "Are there any cycles?" — must check every node
- "Who depends on the database?" — must trace every path
- "What are the entry points?" — must scan all incoming edges

These functions require `nodes` in addition to `edges`:

```nix
graph.cycles g         # nodes in any cycle
graph.dependents g "db"  # who transitively reaches "db"
graph.roots g          # nodes with no incoming edges
```

Internally, these functions **materialize** the graph — they build a complete edge map `{ nodeId = [targets]; }` and compute the transitive closure. This is O(n²) in the worst case, but it only happens once per call, and the result is used for O(1) lookups.

## The transitive closure: seeing everything at once

The **transitive closure** is "if A reaches B and B reaches C, then A reaches C" applied exhaustively. gen-graph computes it via Arntzenius & Krishnaswami's (2016) monotone fixpoint:

```nix
closure = graph.transitiveClosure g;
# closure."web" → [ "api" "cache" "db" ]  — everything web can reach
# closure."gateway" → [ "api" "cache" "db" "web" ] — the full picture
```

The fixpoint iteration (from *Datafun*) works like this:
1. Start with direct edges
2. Compose the current map with the original (discover two-hop paths)
3. Union the result with what we had
4. Repeat until nothing changes

gen-graph enforces **monotonicity** — each iteration must add edges, never remove them. If a step shrinks the graph, something is wrong, and gen-graph throws. This guarantee comes directly from Arntzenius's lattice-theoretic framework: queries over monotone functions always converge.

## Edge map algebra: Mokhov's algebraic graphs

Once you have materialized edge maps, gen-graph provides set operations from Mokhov (2017):

```nix
a = graph.materialize g1;
b = graph.materialize g2;

graph.unionEdges a b       # merge two graphs
graph.intersectEdges a b   # edges present in both
graph.differenceEdges a b  # edges in a but not b
```

The **transitive reduction** (also from Mokhov) answers: "what's the minimal graph that preserves all reachability?"

```nix
minimal = graph.transitiveReduction g;
# Removes edge a→c when a→b→c already provides the path
```

This is useful for diagram clarity — show only the essential structure, hide redundant shortcut edges.

## Composition: relational algebra on edges

`compose` implements relational composition of edge maps:

```nix
# If a→b in map1, and b→c in map2, then a→c in the composition
twoHop = graph.compose (graph.materialize g) (graph.materialize g);
```

This is the engine behind `transitiveClosure` — iterating `compose` to fixpoint computes all transitive edges. But it's also a public API: you might compose a "depends-on" graph with a "deployed-on" graph to find "what hardware does this service indirectly use?"

## Filtering: select and selectEdges

Two filtering operations serve different needs:

**`select`** filters nodes by their data (uses the `nodeData` accessor):

```nix
graph.select g (d: d.type == "backend")   # [ "api" "worker" ]
```

**`selectEdges`** filters a materialized edge map by a predicate on (from, to) pairs:

```nix
em = graph.materialize g;
graph.selectEdges (from: to: to == "db") em
# Only edges pointing at "db": { api = ["db"]; worker = ["db"]; }
```

## The mock utility: building graphs for testing

For tests and exploration, `graph.mock.mkGraph` builds accessor records from simple declarations:

```nix
g = graph.mock.mkGraph {
  edges = [
    { from = "a"; to = "b"; }
    { from = "b"; to = "c"; }
  ];
  parents = [
    { from = "child"; to = "parent"; }
  ];
  nodeData = {
    a = { label = "start"; };
  };
};

graph.reachableFrom g "a"    # [ "b" "c" ]
graph.ancestorsOf g "child"  # [ "parent" ]
```

If you have data in the old node-map format (like scope-engine produces), `fromNodeMap` adapts it:

```nix
legacy = {
  "svc:web" = { imports = [ "svc:api" ]; parent = null; };
  "svc:api" = { imports = [ "svc:db" ]; parent = "svc:web"; };
  "svc:db" = { imports = []; parent = "svc:api"; };
};
g = graph.mock.fromNodeMap legacy;
graph.reachableFrom g "svc:web"   # [ "svc:api" "svc:db" ]
graph.ancestorsOf g "svc:db"      # [ "svc:api" "svc:web" ]
```

## How gen-graph fits the gen ecosystem

gen-graph is the **query layer** — it answers structural questions about graphs that other libraries build:

```
gen-schema  →  defines what kinds of entities exist (types, instances)
gen-scope   →  evaluates attributes on graph nodes (HOAG evaluator)
gen-graph   →  queries the graph structure (reachability, cycles, impact)
gen-aspects →  classifies and dispatches aspect types
gen-select  →  selector algebra for targeting nodes
gen-bind    →  injects args into NixOS modules
```

gen-scope uses gen-graph's accessor pattern: scope-engine memoizes attribute evaluation via `_eval` attrsets (Nix values are lazy), and gen-graph queries operate over those memoized accessors. The memoization IS the cache — gen-graph never caches, it relies on the accessor backend (gen-scope's lazy attrsets) for O(1) repeated calls.

## Summary of operations

| Function | Needs | Behavior |
|----------|-------|----------|
| `reachableFrom` | `edges` | C-level BFS from start node |
| `reachableWhere` | `edges` | C-level BFS + filter by predicate |
| `canReach` | `edges` | Point query: can A reach B? |
| `selfReachable` | `edges` | Is node in a cycle? |
| `ancestorsOf` | `parent` | Walk P-edge chain upward |
| `pathsBetween` | `edges` | All acyclic paths (DFS) |
| `cycles` | `edges`, `nodes` | Nodes in any cycle (per-node C-level BFS) |
| `dependents` | `edges`, `nodes` | Reverse reachability (full closure) |
| `dependentsOf` | `edges`, `nodes` | Reverse reachability (single-target, efficient) |
| `impactOf` | `edges`, `nodes` | Alias for `dependentsOf` |
| `transpose` | `edges`, `nodes` | Reverse all edges |
| `roots` | `edges`, `nodes` | No incoming edges |
| `leaves` | `edges`, `nodes` | No outgoing edges |
| `select` | `nodes`, `nodeData` | Filter by node data predicate |
| `materialize` | `edges`, `nodes` | Build edge map |
| `materializeParents` | `parent`, `nodes` | Build parent map |
| `transitiveClosure` | `edges`, `nodes` | All transitive edges |
| `transitiveReduction` | `edges`, `nodes` | Minimal equivalent graph |
| `fixpoint` | (edge maps) | Iterate to convergence |
| `compose` | (edge maps) | Relational composition |
| `unionEdges` | (edge maps) | Merge with dedup |
| `intersectEdges` | (edge maps) | Common edges |
| `differenceEdges` | (edge maps) | Edges in A not in B |
| `selectEdges` | (edge maps) | Filter by (from, to) predicate |

## Fleet scale: graphs with thousands of nodes

gen-graph is designed for infrastructure at scale — fleets of hundreds or thousands of hosts. Here's how to use it effectively.

### Use point queries before global analysis

For "can A reach B?" questions, don't compute the full transitive closure:

```nix
# DON'T: materializes O(n²) closure
closure = graph.transitiveClosure g;
answer = builtins.elem "db" (closure."web" or []);

# DO: visits only nodes on the path
answer = graph.canReach g "web" "db";
```

### Partition large graphs

For global operations (`cycles`, `dependents`, `roots`), partition the graph by environment or datacenter before querying:

```nix
# DON'T: 10,000 nodes
graph.cycles { edges; nodes = allFleetNodes; }

# DO: 500 nodes per partition
lib.concatMap (env:
  graph.cycles { inherit edges; nodes = nodesInEnv env; }
) environments
```

Cross-partition edges are rare in practice. Per-partition analysis is typically 100-400x faster.

### Use `dependentsOf` for single targets

```nix
# DON'T: computes full O(n²) closure for one question
graph.dependents g "db"

# DO: builds reverse index O(n) + C-level BFS O(reachable)
graph.dependentsOf g "db"
```

Both return the same result. `dependentsOf` is ~n/reachable faster for single targets.

### Accessor memoization is your friend

When gen-graph's accessors are wired to gen-scope's `result.get id "imports"`:

```nix
g = {
  edges = id: result.get id "imports";  # memoized by gen-scope's _eval
  nodes = builtins.attrNames (result.subtreeOf "env:prod");
};
```

- Each `edges id` call hits gen-scope's cached `_eval` → O(1) after first eval
- gen-graph never causes redundant evaluation
- `subtreeOf` limits materialization to one environment's subtree

### Performance summary by operation

| If you need... | Use | Cost |
|----------------|-----|------|
| "Can A reach B?" | `canReach` | O(reachable from A) |
| "What depends on X?" (one X) | `dependentsOf` | O(n + reachable) |
| "What depends on X, Y, Z?" | `dependents` × 1 | O(n²) amortized |
| "Is this node in a cycle?" | `selfReachable` | O(reachable from node) |
| "List all cycles" | `cycles` | O(n × reachable), C-level |
| "Entry points" | `roots` | O(n × degree) |
| "Minimal diagram" | `transitiveReduction` | O(n²) — needs closure |
| "All paths A→B" | `pathsBetween` | O(paths) — small subgraphs only |

Everything labeled "C-level" uses `builtins.genericClosure` — Nix's native C implementation of BFS with built-in dedup. This is ~4-5x faster than equivalent Nix-level traversal on 5000+ node graphs.

## References

The papers behind gen-graph's design, in order of influence:

1. **Néron, P. et al. (2015)** — *A Theory of Name Resolution.* The P/I edge model. Parent edges form trees (lexical scoping); import edges form DAGs (module composition). gen-graph's two accessor types (`parent`, `edges`) directly implement this distinction.

2. **Mokhov, A. (2017)** — *Algebraic Graphs with Class.* Edge map set operations (union, intersect, difference) as a closed algebra. Transitive reduction as "closure minus composed edges." gen-graph's edge-map operations follow this framework.

3. **Arntzenius, M. & Krishnaswami, N. (2016)** — *Datafun: A Functional Datalog.* Monotone fixpoint computation over finite lattices. gen-graph's `fixpoint` enforces monotonicity (growing edge count), guaranteeing convergence. `reachableWhere` draws from Datafun's predicate-filtered queries.

4. **Kahn, G. (1974)** — *The Semantics of a Simple Language for Parallel Programming.* Demand-driven evaluation — only compute what's asked for. gen-graph's lazy traversal (only visiting reachable nodes) is this principle applied to graph queries in a lazy language.

5. **Radul, A. (2009)** — *The Art of the Propagator.* Computations as networks of independent cells connected by propagators. gen-graph's accessor pattern (queries compose via function arguments, not shared mutable state) follows this philosophy of decoupled, composable computation.
