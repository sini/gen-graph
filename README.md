# gen-graph — Monotonic Query Combinators over Scope Graphs

Datafun-inspired ([Arntzenius & Krishnaswami 2016](https://www.cl.cam.ac.uk/~nk480/datafun.pdf)) query combinators for graph analysis over node maps. Two layers: composable monotonic combinators (foundation) and built-in query primitives (convenience).

## Overview

gen-graph is a pure analysis layer. It does **not** construct graphs, resolve names, or evaluate attributes — those are separate concerns. gen-graph takes a computed node map and answers questions about it.

```nix
# Given a node map
nodes = {
  web = { id = "web"; imports = [ "api" ]; parent = null; decls = {}; type = "frontend"; };
  api = { id = "api"; imports = [ "database" "cache" ]; parent = null; decls = {}; type = "backend"; };
  database = { id = "database"; imports = []; parent = null; decls = {}; type = "datastore"; };
  cache = { id = "cache"; imports = []; parent = null; decls = {}; type = "datastore"; };
};

# Query with gen-graph
graph.reachableFrom nodes "web"         # → [ "api" "cache" "database" ]
graph.dependents nodes "database"       # → [ "api" "web" ]
graph.roots nodes                       # → [ "web" ]
graph.leaves nodes                      # → [ "cache" "database" ]
graph.cycles nodes                      # → []
```

## Terminology

| Term | Definition |
|------|-----------|
| Nodes | Graph vertices — plain attrsets with id, parent, imports, decls, type |
| Edges | Labeled relationships between nodes: I (import), P (parent), custom |
| Combinators | Query builders: select, compose, fixpoint |

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen](https://github.com/sini/gen) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |

## Quick Start

### As a flake input

```nix
{
  inputs = {
    gen-graph.url = "github:sini/gen-graph";
  };
  outputs = { gen-graph, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      graph = gen-graph { inherit lib; };
    in { /* use graph.reachableFrom, graph.dependents, etc. */ };
}
```

### Without flakes

```nix
let
  lib = (import <nixpkgs> {}).lib;
  graph = import ./path/to/gen-graph { inherit lib; };
in
graph.reachableFrom nodes "web"
```

## Result Sets

gen-graph operates on **result sets** — attrsets keyed by identity for O(1) membership checking.

```nix
# Node sets: { nodeId = nodeRecord; }
nodeSet = graph.fromNodes nodes;

# Edge sets use two-level attrsets: { from = { to = edgeRecord; }; }
edgeSet = graph.fromEdges nodes;
```

## Layer 1: Monotonic Combinators

All operations are monotonic — result sets can only grow during fixpoint iteration, guaranteeing termination ([Arntzenius §2](https://www.cl.cam.ac.uk/~nk480/datafun.pdf)).

### Filtering

```nix
# Filter nodes by predicate
graph.select nodes (n: n.type == "backend")

# Filter edges by predicate
graph.selectEdges edgeSet (e: e.label == "I")
```

### Set Operations

```nix
graph.unionNodes a b          # monotonic node set union
graph.unionEdges a b          # monotonic edge set union
graph.intersectNodes a b      # node set intersection
graph.intersectEdges a b      # edge set intersection
graph.differenceEdges a b     # edge set difference (a minus b)
```

### Relational Composition

```nix
# a→b + b→c = a→c
graph.compose edges1 edges2
```

### Fixed-Point Iteration

The core Datafun primitive. Iterates a step function until the result stabilizes.

```nix
closure = graph.fixpoint {
  seed = importEdges;
  step = current: graph.unionEdges current (graph.compose current importEdges);
  maxIter = 1000;  # safety bound (default)
};
```

**Monotonicity enforcement:** `fixpoint` checks that the result set doesn't shrink between iterations (top-level key count). Convergence uses structural equality (`==`). If a user-supplied step function is non-monotonic, the runtime check catches it.

## Layer 2: Built-In Primitives

Common queries built on the combinators.

### `reachableFrom`

All nodes transitively reachable from a start node (via import edges).

```nix
graph.reachableFrom nodes "web"  # → [ "api" "cache" "database" ]
```

### `reachableWhere`

Predicate-filtered reachability. Returns nodes transitively reachable from `startId` that match `pred`.

```nix
reachableWhere nodes startId pred
```

### `dependents`

All nodes that transitively lead to a target node.

```nix
graph.dependents nodes "database"  # → [ "api" "cache" "web" ]
```

### `impactOf`

Alias for `dependents` — "what breaks if this node goes down?"

```nix
graph.impactOf nodes "database"  # → [ "api" "cache" "web" ]
```

### `ancestorsOf`

Walks P-edges (parent chain) upward from `startId`. Cycle-protected.

```nix
ancestorsOf nodes startId → [ parentId grandparentId ... ]
```

### `pathsBetween`

All acyclic paths between two nodes (DFS with cycle prevention).

```nix
# Diamond: a → b → d, a → c → d
graph.pathsBetween nodes "a" "d"  # → [ [ "a" "b" "d" ] [ "a" "c" "d" ] ]
```

### `roots`

Nodes with no incoming import edges.

```nix
graph.roots nodes  # → [ "web" ]
```

### `leaves`

Nodes with no outgoing import edges.

```nix
graph.leaves nodes  # → [ "cache" "database" ]
```

### `cycles`

Nodes participating in any cycle (self-reachable in the transitive closure).

```nix
# Cyclic: a → b → c → a
graph.cycles cyclicNodes  # → [ "a" "b" "c" ]

# Acyclic
graph.cycles dagNodes     # → []
```

### `transitiveReduction`

Minimal edge set preserving reachability. Removes redundant transitive edges.

```nix
transitiveReduction nodes → edgeSet
```

## Utility Functions

```nix
graph.fromNodes nodes           # identity (node map is the native format)
graph.fromEdges nodes           # extract all edges (P, I, custom) as two-level attrset
graph.emptyNodes                # {}
graph.emptyEdges                # {}
graph.sizeNodes nodeSet         # count nodes
graph.sizeEdges edgeSet         # count total edges
graph.memberNode nodeSet "id"   # bool
```

### `mock` (test utility)

Public test utility for constructing node maps without gen-scope.

```nix
graphLib.mock.mkNodes { edges ? [], parents ? [], decls ? {}, types ? {} }
graphLib.mock.fixtures.{diamond, chain, cyclic, tree, serviceGraph}
```

## Integration with gen-schema

gen-schema's `buildInstanceGraph` produces node maps compatible with gen-graph. The pipeline:

```nix
# gen-schema produces the data
instanceGraph = schema.buildInstanceGraph mySchema fleet;

# gen-graph queries it
graph.dependents instanceGraph.nodes "service:postgres"
```

## Architecture

```
gen-graph/
  flake.nix                — inputs: nixpkgs only
  default.nix              — { lib } entry point
  lib/
    default.nix            — aggregates sets + combinators + primitives
    sets.nix               — result set operations (fromNodes, fromEdges, union, intersect, size)
    combinators.nix        — Arntzenius 2016 monotonic combinators (select, compose, fixpoint)
    primitives.nix         — built-in queries (reachableFrom, dependents, cycles, etc.)
  templates/
    ci/                    — test suite (40 tests)
```

## Academic Foundations

| Feature | Paper |
|---------|-------|
| Monotonic combinators, fixpoint | [Arntzenius & Krishnaswami — *Datafun: A Functional Datalog* (ICFP 2016)](https://www.cl.cam.ac.uk/~nk480/datafun.pdf) |
| Scope graph node format | [Néron et al. — *A Theory of Name Resolution* (ESOP 2015)](https://link.springer.com/chapter/10.1007/978-3-662-46669-8_9) |
| Algebraic graph construction | [Mokhov — *Algebraic Graphs with Class* (Haskell 2017)](https://dl.acm.org/doi/10.1145/3122955.3122956) |

## Testing

```bash
nix flake check --override-input gen-graph . ./templates/ci
```

## License

MIT
