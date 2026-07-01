# gen-graph demo: accessor-based graph queries

A standalone flake showing `gen-graph` operating over a small microservice
dependency graph via an **accessor record** — a `{ edges, parent, nodes, nodeData }` view over arbitrary data, with no need to materialize the graph up
front.

```
  gateway → web → api → database
                     → cache
  worker → database
         → queue
```

Diamond pattern: `gateway` and `worker` both reach `database` by different
paths. Two roots (`gateway`, `worker`), three leaves (`database`, `cache`,
`queue`).

## Run it

Each output attribute is an independent query result. Evaluate any of them:

```sh
nix eval .#webReaches       # → [ "api" "database" "cache" ]
nix eval .#databaseImpact   # → [ "api" "gateway" "web" "worker" ]
nix eval .#detectedCycles   # → [ "api" "cache" ]
nix eval .#backends         # → [ "api" "worker" ]
```

## What it demonstrates

**Lazy traversal** (no full materialization):

- `reachableFrom` — transitive reachability (BFS discovery order, not sorted)
- `pathsBetween` — all paths between two nodes
- `reachableWhere` — predicate-filtered reachability

**Global analysis:**

- `dependents` — reverse transitive reachability ("what breaks if X goes down?")
- `cycles` — cycle detection on a DAG (empty) and on a graph with a back edge
- `transpose` — the reversed graph

**Enumeration:**

- `roots` / `leaves` — entry points and sinks
- `select` — filter nodes by their data

**Materialization + edge-map operations:**

- `materialize` — accessor record → explicit edge map
- `transitiveClosure` / `transitiveReduction`
- `selectEdges` — filter edges by endpoints
- `compose` — relational composition (two-hop reachability)

**Registry adapter:**

- `fromRegistry` + `field` — build an accessor record from a declarative node
  registry (nixpkgs-style `imports` + `parent`), then run `reachableFrom` /
  `ancestorsOf` over it.

## Notes on ordering

Traversal results follow `builtins.genericClosure` BFS discovery order, not a
sorted order. Comments in `flake.nix` show the exact current results.
