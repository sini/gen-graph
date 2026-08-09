# gen-graph — agent capability sheet

## Scope

Accessor-based graph query combinators: the caller supplies `edges` / `nodes` / `parent` / `nodeData` (or `labeledEdges`) as plain functions, and gen-graph returns reachability, SCC condensation, phase order, edge-map algebra, pre-order folds, and label-regex queries over them — it never stores the graph.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| Building the data the accessors read; demand-driven attribute evaluation over scope graphs | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs" |
| Predicates over graph positions (selector algebra, `matches`) | `gen-select` — "gen-select: selector algebra for attributed graph positions". gen-graph's `where` / `select` / `prune` take a bare Nix predicate; there is no selector import |
| Choosing a winner among matched rules (the dispatch STEP) | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)". `lib/order.nix:3-4` records that `phaseOrder` absorbed gen-dispatch's `dag.nix` (`entry*`/`topoSort`), so ordering lives here and dispatch there |
| Graph PRODUCTS — Cartesian/tensor/strong/lexicographic, cells, slices, fibers, quotients | `gen-product` — "gen-product — graph products as first-class operations over accessor-graphs (Cartesian / tensor / strong / lexicographic; cells, slices, fibers, projections, quotients, restriction, containment chains), lazy in and out" |
| Minting identity, kinds, instances, registries | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system". `fromRegistry` consumes a caller-supplied attrset and mints nothing |
| Type checking / `verify` | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| General utilities — gen-graph's ONLY dependency | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem" |
| Incremental rebuild / change propagation / AFFECTED sets | `gen-rebuild` — "gen-rebuild: pure-Nix incremental rebuilder core (Mokhov rebuilder dimension)". Consumes gen-graph |
| Content movement, edge materialization fold, edge-trace parity | `gen-edge` — "gen-edge — the content-movement contract: the (S,T,P,M) edge algebra, toposorted materialization fold, and the frozen edge-trace parity oracle". Consumes gen-graph |
| Typed demand cascade / stratified demand resolution | `gen-demand` — "gen-demand — typed demand cascade (kinds resolve demands into resources + wiring + sub-demands; a stratified, terminating fold resolves the multiset with full provenance)". Consumes gen-graph |
| RAG attribute schedule + convergence loop | `gen-resolve` — "gen-resolve — demand-driven higher-order RAG evaluator over algebraic scope graphs (Knuth 1968 attribute schedule + Vogt 1989 HOAG)" |
| Channels / dataflow that consume a graph | `gen-pipe` — "gen-pipe — scoped channels + dataflow algebra (map/filter/fold/scan/route/join/tee) with B5 determinism, provenance, dedup, and class-aware contributions" |

## Exports

Entry: `inputs.gen-graph.lib` (flake). Root `default.nix` is a FUNCTION `{ prelude ? <derived from flake.lock via fetchTree>, ... }` — `import ./. { }` works standalone; `import ./lib { prelude = …; }` requires the argument.

**Accessor contract** (consumed, not exported). `edges : id -> [id]`, `nodes : [id]`, `parent : id -> id|null`, `nodeData : id -> attrset`. Each combinator destructures only what it needs (`{ edges, ... }`, `{ edges, nodes, ... }`, …). Labeled queries take a separate shape: `labeledEdges : id -> [{ label; target; }]`. An **edge map** is `{ <from> = [to]; }`.

**Lazy traversal** — `lib/traverse.nix` (pure builtins, no prelude; `genericClosure`-backed)

| Export | Signature |
|---|---|
| `reachableFrom` | `{ edges } -> id -> [id]` |
| `reachableWhere` | `{ edges } -> id -> (id -> bool) -> [id]` |
| `canReach` | `{ edges } -> from -> to -> bool` |
| `selfReachable` | `{ edges } -> id -> bool` |
| `ancestorsOf` | `{ parent } -> id -> [id]` |
| `pathsBetween` | `{ edges } -> from -> to -> [[id]]` (acyclic paths) |

**Global analysis** (materializes internally) — `lib/global.nix`

| Export | Signature |
|---|---|
| `cycles` | `{ edges, nodes } -> [id]` (membership, key-sorted) |
| `cyclePaths` | `{ edges, nodes } -> [[id]]` (one ORDERED representative cycle per cyclic component) |
| `dependents` | `{ edges, nodes } -> id -> [id]` (closure + transpose; amortized for many targets) |
| `dependentsOf` | `{ edges, nodes } -> id -> [id]` (reverse index + BFS; single target) |
| `impactOf` | alias of `dependentsOf` |
| `dependentsFrontier` | `{ edges, nodes } -> id -> (id -> bool) -> [id]` (prune = expand-this-node?) |
| `directDependents` | `{ edges, nodes } -> edgeMap` (immediate reverse adjacency) |
| `directDependentsOf` | `{ edges, nodes } -> id -> [id]` |
| `transpose` | `{ edges, nodes } -> { edges; nodes; }` |
| `coScc` | `{ edges } -> u -> v -> bool` |
| `condensation` | `{ edges, nodes } -> { reps; bottomUp; members; sccs; sccOf; condEdges; }` — `members : tag -> [id]`, `condEdges : tag -> [tag]`, `sccOf : id -> tag`, `reps == bottomUp` |
| `coneRank` | `accessor -> [id] -> { order; depth; }` (cone-local, `edges` read as producers) |

**Ordering (phase DAG)** — `lib/order.nix`

| Export | Signature |
|---|---|
| `entryAnywhere` | `entry` (a value, not a function) |
| `entryAfter` | `[name] -> entry` |
| `entryBefore` | `[name] -> entry` |
| `entryBetween` | `[before] -> [after] -> entry` |
| `phaseOrder` | `{ <name> = entry; } -> [name]` (forward, producers-first; throws on cycles) |

**Fixpoint / closure** — `lib/fixpoint.nix`

| Export | Signature |
|---|---|
| `fixpoint` | `{ seed, step, maxIter ? 1000 } -> edgeMap` (monotonicity-guarded) |
| `seededFixpoint` | `{ seed, frontier, step, maxIter ? 1000 } -> edgeMap` (semi-naive; `step dF acc`) |
| `compose` | `edgeMap -> edgeMap -> edgeMap` |
| `transitiveClosure` | `{ edges, nodes } -> edgeMap` |
| `transitiveReduction` | `{ edges, nodes } -> edgeMap` (assumes a DAG) |

**Edge maps** — `lib/edge-maps.nix`

| Export | Signature |
|---|---|
| `materialize` | `{ edges, nodes } -> edgeMap` |
| `materializeParents` | `{ parent, nodes } -> { <id> = parentId; }` |
| `unionEdges` / `intersectEdges` / `differenceEdges` | `edgeMap -> edgeMap -> edgeMap` |
| `selectEdges` | `(from -> to -> bool) -> edgeMap -> edgeMap` |

**Enumeration** — `lib/enumerate.nix`

| Export | Signature |
|---|---|
| `roots` | `{ edges, nodes } -> [id]` (no incoming edge) |
| `leaves` | `{ edges, nodes } -> [id]` (no outgoing edge) |
| `select` | `{ nodes, nodeData } -> (data -> bool) -> [id]` |

**Pre-order folds** (ordered, payload-carrying, label-exposing) — `lib/preorder.nix`

| Export | Signature |
|---|---|
| `foldPreorder` | `{ roots, key, expand, acc, visited ? {} } -> { acc; visited; }` — `expand acc frame -> { acc; children ? [] }` |
| `expandPreorder` | `{ roots, key, edges, resolve ? id, emit ? (_: p: p), seen0 ? {}, nodes0 ? [] } -> { nodes; seen; }` |
| `foldReach` | `{ roots, edges, target, project, itemKey, visited0 ? {}, seen0 ? {}, nodes0 ? [] } -> { nodes; seen; visited; }` |

**Construction and fixtures** — `lib/registry.nix`

| Export | Signature |
|---|---|
| `fromRegistry` | `{ registry, edges, parent ? (_id: _entry: null) } -> { nodes; edges; parent; nodeData; }` |
| `field` | `name -> id -> entry -> [id]` (edge extractor for `fromRegistry`) |
| `fields` | `[name] -> id -> entry -> [id]` |
| `mkGraph` | `{ edges ? [], parents ? [], nodeData ? {} } -> { edges; parent; nodes; nodeData; }` — edge lists are `[{ from; to; }]` |
| `fixtures` | `{ chain, cyclic, diamond, disconnected, serviceGraph, tree }` (public, see traps) |
| `labeledFixtures` | `{ cyclic, poisoned, world }` (public, see traps) |

**Labeled queries** — `lib/query.nix`

| Export | Signature |
|---|---|
| `labeledFrom` | `{ <label> = id -> [id]; } -> { labeledEdges; }` |
| `query` | `{ graph, from, follow, where ? (_: true), mode ? "all", … } -> answers` |
| `queryFold` | `{ graph, from, follow, where ?, empty, combine, valueOf ? (id: id) } -> value` |

`query` modes and their return shapes: `all` ⇒ `[id]` (sorted set); `paths` ⇒ `[{ node; path; }]` with `path = [{ label; from; to; }]`; `visible` ⇒ `{ visible; shadowed; }` (extra args `order`, `groupBy ? (ans: ans.node)`); `layers` ⇒ `[[answer]]` (extra arg `order`); `fixpoint` ⇒ dispatches to `queryFold`. `order = { labels ? []; endOfPath ? -1; }`. Any other mode throws. `queryAll` / `queryPaths` / `queryVisible` / `queryLayers` are internal — only `query`, `queryFold` and `labeledFrom` are exported.

**Label regex** — `lib/regex.nix`, reached as `regex.*` (the only nested namespace)

| Export | Signature |
|---|---|
| `eps` / `empty` / `any` | `re` (values) |
| `lit` | `label -> re` |
| `seq` / `alt` | `[re] -> re` (normalize on construction) |
| `star` / `opt` / `plus` | `re -> re` |
| `nullable` | `re -> bool` |
| `deriv` | `label -> re -> re` (Brzozowski) |
| `stateKey` | `re -> string` (canonical, ACI-normal) |
| `parse` | `string -> re` — grammar `expr := seqE ("\|" seqE)*`, `seqE := post+`, `post := atom ("*"\|"?"\|"+")?`, `atom := LABEL \| "_" \| "(" expr ")"` |

## Entry points by task

| Task | Reach for |
|---|---|
| What can this node reach? | `reachableFrom acc id` (lazy — never enumerates `nodes`) |
| Can A reach B? | `canReach acc a b` (no materialization) |
| What breaks if I change this node? | `dependentsOf acc id` (or `impactOf`); `dependents` only when querying many targets |
| Immediate reverse neighbours only | `directDependentsOf acc id` / `directDependents acc` |
| Reverse cone with an early cutoff | `dependentsFrontier acc id prune` |
| Detect cycles | `cycles acc`, or `selfReachable acc id` for one node |
| Name the loop in a diagnostic (ordered, edges real) | `cyclePaths acc` — NOT `cycles`, whose key-sorted set renders edges that do not exist |
| Collapse SCCs / get a quotient DAG | `condensation acc` |
| Order home-manager-style before/after phases | `entryAfter` / `entryBefore` / `entryBetween` + `phaseOrder` |
| Rank a dependent cone producers-first without whole-graph condensation | `coneRank acc cone` |
| Full transitive closure as data | `transitiveClosure acc` |
| Minimal edge set of a DAG | `transitiveReduction acc` |
| Custom monotone edge-map iteration | `fixpoint` / `seededFixpoint` (semi-naive) |
| Combine two edge maps | `unionEdges` / `intersectEdges` / `differenceEdges` / `selectEdges` |
| Walk a parent chain | `ancestorsOf acc id` |
| Enumerate entry/exit nodes | `roots acc` / `leaves acc` |
| Filter nodes by their data | `select acc pred` (accessor must carry `nodeData`) |
| Build an accessor from an attrset registry | `fromRegistry { registry; edges = field "deps"; }` |
| Build an accessor from literal edge lists | `mkGraph { edges = [ { from; to; } ]; }` |
| DFS pre-order fold with a caller-owned accumulator | `foldPreorder` (the primitive) |
| Ordered witness list over demand-generated successors | `expandPreorder` |
| Labeled, suppression-aware reach with per-edge projection | `foldReach` |
| Reachability constrained by a path-label regex | `query { graph; from; follow = regex.parse "contains*"; }` |
| Resolution traces / shadowing explanations | `query { … mode = "paths"\|"visible"\|"layers"; }` |
| ACI-lawful aggregation over an answer set | `queryFold` (or `mode = "fixpoint"`) |
| Adapt per-label plain accessors to the labeled contract | `labeledFrom { contains = …; member = …; }` |

## Measured traps

Each row verified in this run against `g = import ./. { }` (root `default.nix`, self-pinned prelude). Shared fixtures: `dia` / `cyc` / `chain` / `tree` / `svc` = `g.fixtures.{diamond,cyclic,chain,tree,serviceGraph}`; `world` / `poisoned` = `g.labeledFixtures.*`; `R = g.regex`.

| Trap | Evidence |
|---|---|
| Ordering does not reach gen-prelude for the ORDER — only for the loop encoding | `grep -rho "prelude\.[a-zA-Z']*" lib/ \| sort -u` ⇒ exactly `concatMap filterAttrs fix foldl' genAttrs imap init iterateBounded listToAttrs mapAttrs mapAttrsToList max unique` (`imap` is the pattern truncating `imap0`), no sort of any kind: `iterateBounded` drives the Kahn loop, it does not decide the order. Control on the same predicate: filtering the prelude's `attrNames` for `sort` ⇒ `["sort"]` — the primitive comparator sort is all that is left there, and `grep -rho "prelude.sort" lib/` returns nothing |
| **No node count caps an ordering** — the Kahn loop is a bounded iteration over the key list, so its evaluator frame cost is constant in `n`; a step that applied itself spent one frame per node and aborted uncatchably around 10^4 | Fixture `g = import ./lib { prelude = import <gen-prelude>/lib; }`, a chain of `n` nodes. `nix-instantiate --eval --strict --option max-call-depth 1000` over a **20000**-node chain ⇒ `{ ok = true; len = 20000; head = "n19999"; }` — twenty times the setting. Live control that the option is honoured at all, same setting same run: `let go = i: acc: if i == 0 then acc else go (i - 1) (acc + 1); in go 5000 0` ⇒ `error: stack overflow; max-call-depth exceeded`, and the same expression without the option ⇒ `5000`. Test (small band): `test-topo-long-chain-has-no-frame-ceiling` (`ci/tests/order.nix`) |
| The remaining bound on ordering is COST, not frames, and it is quadratic | `list.elements` on a chain, `n = 500/1000/2000/4000/8000` ⇒ 136,243 / 522,493 / 2,044,993 / 8,089,993 / 32,179,993 — ×3.98 per doubling, exponent **2.00**; the wide shape at `n = 2000/4000/8000` ⇒ 4,701,672 / 18,738,004 / 74,806,672, same exponent. Floors in the same runs (no gen-graph code): `builtins.sort` `2n + 3` and the deep-forced accessor `4n + 2`, both exponent 1.00 |
| **BEHAVIOUR CHANGE** — `phaseOrder` now REFUSES an `after`/`before` naming a phase outside `entries`; it used to accept it and silently drop the constraint | measured on both trees in one run: the pre-change `phaseOrder { a = entryAfter [ "ghost" ]; b = entryAnywhere; }` ⇒ `["b","a"]` (succeeds, `a` and `b` treated as independent); the same call now ⇒ `tryEval … .success` `false`. Control in the same run, both trees: a well-formed `{ a = entryAnywhere; b = entryAfter [ "a" ]; }` ⇒ `["a","b"]` on each. Test: `test-order-refuses-unknown-phase` (`ci/tests/order.nix`) |
| `topoOrder` succeeds or reports cycles; it never throws for a cycle, and the two arms carry **different** attributes | acyclic ⇒ `{ ok = true; order = …; }` and `? cycles` ⇒ `false`; cyclic ⇒ `{ ok = false; cycles = …; }` and `? order` ⇒ `false`. A caller that reads `.order` without checking `.ok` gets a missing-attribute error, not a silent `null`. Tests: `test-topo-acyclic-control`, `test-topo-cycle-does-not-throw` (`ci/tests/order.nix`) |
| The ready-set pick is the global minimum, **not** the minimum within a level | nodes `z`, `a`, `b` with `b` depending on `a` ⇒ `["a","b","z"]`, not `["a","z","b"]`: once `a` is emitted `b` is ready and beats `z`. This is the rule gen-edge's Law E2 and its frozen trace `E` are a trace of. Test: `test-topo-pick-is-global-min-ready` |
| `topoOrder` REFUSES BY NAME rather than aborting — a non-string `keyOf` output, a key collision, and a dangling edge target are all catchable throws | each of the three ⇒ `tryEval … .success` `false` **with a `gen-graph.topoOrder:` message**; letting a non-string reach `prelude.genAttrs` instead raises a type error `tryEval` cannot catch. Control in the same suite: a well-formed call ⇒ not caught. Tests: `test-topo-refuses-{non-string-key,key-collision,dangling-edge}`, `test-topo-refusal-control` |
| On a DENSE graph `topoOrder` is SLOWER than the `prelude.toposort` it replaced | l4pj's own fixture (a total order, so `E = n(n-1)/2`), wall clock incl. `nix` startup: retired `prelude.toposort` `n=500/1000/2000` ⇒ 0.11/0.34/1.25 s; `topoOrder` on the same fixture ⇒ 0.29/1.07/5.88 s. On a SPARSE fixture (a chain, `E = n-1`) at the same sizes `topoOrder` ⇒ 0.04/0.05/0.09 s against the same 0.11/0.34/1.25 s. Control, same runs: `builtins.sort` ⇒ 0.02 s flat. The accessor model must materialize the edge set and a reverse index (a `{name; value;}` record per edge, then a `groupBy`: 2.32 s and 3.88 s of the 5.88 s at `n=2000`); the comparator-based DFS never did |
| `reachableFrom` excludes `startId` **even when the start is in a cycle**, so it disagrees with `cycles`/`selfReachable` about that node | `lib/traverse.nix:19`; `reachableFrom cyc "a"` ⇒ `["b","c"]` while `selfReachable cyc "a"` ⇒ `true` and `cycles cyc` ⇒ `["a","b","c"]`. `dependents cyc "a"` and `dependentsOf cyc "a"` both ⇒ `["b","c"]`, excluding the target the same way |
| `transpose` returns **only** `{ edges; nodes; }` — `parent` and `nodeData` are dropped, so a transposed accessor cannot feed `select`/`ancestorsOf`, and the failure is an uncatchable eval error, not `false` | `lib/global.nix:transpose`; `attrNames (transpose svc)` ⇒ `["edges","nodes"]`; `select (transpose svc) (_: true)` ⇒ `error: function 'select' called without required argument 'nodeData'` at `lib/enumerate.nix:22:12` (escapes `tryEval`). Positive control: `select svc (d: d.type or "" == "datastore")` ⇒ `["cache","db","queue"]`. Test: `test-transpose-preserves-nodes` (`ci/tests/global.nix`) |
| A `phaseOrder` name that is **not a key of `entries`** behaves **oppositely by direction**: a ghost in `before` is silently dropped, a ghost in `after` is refused by name | `lib/order.nix:entryBetween` + `lib/order.nix:phaseOrder`; `phaseOrder { a = entryBefore ["ghost"]; }` ⇒ `["a"]` **and** `phaseOrder { a = entryBefore ["ghost"]; b = entryAnywhere; }` ⇒ `["a","b"]` — both **exit 0, no throw**, so the second phase does not make it throw; but `phaseOrder { a = entryAfter ["ghost"]; b = entryAnywhere; }` ⇒ `error: gen-graph.topoOrder: edge target "ghost" is not in nodes`. Control in the same run: `phaseOrder { a = entryBefore ["b"]; b = entryBefore ["a"]; }` ⇒ `error: gen-graph.phaseOrder: cyclic ordering constraints`, so the throw path is reachable and the two exit-0 readings are real absences |
| `coneRank` and `phaseOrder` read edge direction **oppositely** | On `chain` (`a→b→c→d`): `coneRank chain ["a" "b" "c" "d"]` ⇒ `{ order = ["d","c","b","a"]; depth = { a=3; b=2; c=1; d=0; }; }` (edge TARGET first — targets are producers, `lib/global.nix:coneRank`), while the same shape as `entryBefore` chains ⇒ `phaseOrder` `["a","b","c","d"]` (edge SOURCE first, `lib/order.nix:21`) |
| `phaseOrder` throws on a cycle **and** on a self-loop (`n after n`), which is a singleton SCC and needs its own check | `lib/order.nix:48-54`; both `tryEval` runs ⇒ `success = false`. Tests: `test-order-cycle-throws`, `test-order-self-loop-throws` (`ci/tests/order.nix`) |
| `mkGraph`'s `parents` create **no** `edges` — the two indices are disjoint | `lib/registry.nix:60-71`; `tree.edges "child1"` ⇒ `[ ]` while `tree.parent "child1"` ⇒ `"root"` and `ancestorsOf tree "grandchild"` ⇒ `["child1","root"]`. Test: `test-tree-parent` (`ci/tests/registry.nix`) |
| `roots` and `leaves` are **both empty** on a fully cyclic graph — emptiness is not "no such node" | `lib/enumerate.nix:3-20`; `roots cyc` ⇒ `[ ]`, `leaves cyc` ⇒ `[ ]`. Positive control: `roots dia` ⇒ `["a"]`, `leaves dia` ⇒ `["d"]` |
| Edge-map set ops are asymmetric about empty rows: `unionEdges` **keeps** them, `differenceEdges`/`intersectEdges`/`selectEdges` **drop** the key entirely | `lib/edge-maps.nix:33` vs `47-63`; `unionEdges { a = []; } { b = ["x"]; }` ⇒ `{ a = []; b = ["x"]; }`; `differenceEdges { a = ["x"]; b = ["y"]; } { a = ["x"]; }` ⇒ `{ b = ["y"]; }`; `intersectEdges { a = ["x"]; b = ["y"]; } { a = ["z"]; }` ⇒ `{ }` |
| `materialize` keys only on `nodes`: a target outside `nodes` appears as a value but never as a key, so the result is not a closed edge map | `lib/edge-maps.nix:3`; `materialize { nodes = ["a"]; edges = _: ["offgraph"]; }` ⇒ `{ a = ["offgraph"]; }` |
| `fixpoint`'s monotonicity guard counts **edges**, not nodes or iterations, and both it and `maxIter` throw rather than returning the partial result | `lib/fixpoint.nix:5-32`; a step shrinking `["x","y"]`→`["x"]` ⇒ `tryEval success = false`; a never-converging step with `maxIter = 3` ⇒ `false`. Positive control: a one-step growth converges ⇒ `{ a = ["x","y"]; }`. Tests: `test-fixpoint-monotonicity-violation`, `test-fixpoint-max-iter` (`ci/tests/fixpoint.nix`) |
| `transitiveReduction` assumes a DAG: on a cycle it returns the input **unchanged** — no reduction, no throw | `lib/fixpoint.nix:79-103` and README's own "assumes a DAG, since reduction is not unique under cycles"; `transitiveReduction cyc` ⇒ `{ a = ["b"]; b = ["c"]; c = ["a"]; }`. Positive control: `transitiveReduction dia` ⇒ `{ a = ["b","c"]; b = ["d"]; c = ["d"]; }` |
| `query` in `all` mode answers the `from` node **itself** whenever `follow` is nullable | `lib/query.nix:76-83`; `follow = R.parse ""` ⇒ `["root"]`; `"contains*"` ⇒ `["h1","h2","root","u1","u2","vm1"]`; `"contains+"` ⇒ the same minus `root`. Test: `test-all-non-nullable-excludes-from` (`ci/tests/query.nix`) |
| `where` filters the **answer set**, not the walk — a blocked node still conducts traversal through itself | `lib/query.nix:80`; `where = n: n != "h1"` ⇒ `["h2","root","u1","u2","vm1"]`, i.e. `u1`/`vm1`/`u2` (reachable only through `h1`) still answer. Positive control, no `where`: `["h1","h2","root","u1","u2","vm1"]`. Test: `test-all-where-filters` (`ci/tests/query.nix`) |
| In `visible` mode the default `groupBy` is per-node, so shadowing can only ever occur between multiple paths to the **same** node — differently-ranked answers at different nodes never shadow each other | `lib/query.nix:194,204`; two paths to one node (`own` vs `imp own`) ⇒ `visible = [["own"]]`, `shadowed = [["imp","own"]]`; but from `g1` over `world` with `order.labels = ["member" "include"]`, `visible` ⇒ `["shared","u1","u2"]` and `shadowed` ⇒ `[ ]` (three distinct nodes, three groups). Test: `test-visible-default-group-no-cross-shadow` (`ci/tests/query.nix`) |
| Laziness is **derivative-driven**: an accessor is left unforced only when the label derivative goes empty on the edge that reaches it | `lib/query.nix:58-59`, `lib/registry.nix:292-313`; `query { graph = poisoned; follow = R.parse "safe*"; }` ⇒ `["a","b"]` (the `boom` accessor throws if forced), while `follow = R.parse "_*"` on the same graph ⇒ throws. Test: `test-laziness-poison-unreached` (`ci/tests/query.nix`) |
| `regex.parse ""` is `eps`, not "match anything"; a lone `_` is the any-label wildcard but `_` inside a longer token is an ordinary label character | `lib/regex.nix:216,291-298`; `stateKey (parse "")` ⇒ `"e"`, `stateKey (parse "_")` ⇒ `"_"` (any), `stateKey (parse "a_b")` ⇒ `"'a_b"` (literal) |
| `regex.parse` throws on any character outside `[A-Za-z0-9_-]` plus the operators, and on malformed operator placement — labels carrying `.` or `/` cannot be parsed | `lib/regex.nix:169,200,229,272`; `parse "a.b"`, `parse "*a"`, `parse "(a"`, `parse "()"` all ⇒ `tryEval success = false`. Positive control: `stateKey (parse "contains*")` ⇒ `"'contains*"`. Constructors (`lit`/`seq`/`alt`) bypass the parse alphabet; `lib/regex.nix:7-10` states the caller then owns the `stateKey` collision constraint |
| `foldPreorder` never cycle-guards a frame whose `key` is `null` — the same frame is folded once per occurrence | `lib/preorder.nix:58-62`; `roots = [1 2 1]` with `key = _: null` ⇒ acc `[1,2,1]`; same roots with `key = toString` ⇒ `[1,2]`. Test: `test-foldpreorder-null-key-unguarded` (`ci/tests/preorder.nix`) |
| `dependentsFrontier` **includes** a pruned node in the result but does not expand it | `lib/global.nix:dependentsFrontier`; `dependentsFrontier svc "db" (n: n != "api")` ⇒ `["api","worker"]` — `api` present, `web` (reachable only through `api`) cut. Positive control: `dependentsOf svc "db"` ⇒ `["api","web","worker"]`. Test: `test-frontier-pruned-boundary-present` (`ci/tests/global.nix`) |
| `condensation.sccOf` on an unknown id returns the id itself rather than throwing | `lib/global.nix:condensation`; `(condensation cyc).sccOf "nope"` ⇒ `"nope"`, while `(condensation cyc).sccs` ⇒ `[["a","b","c"]]` |
| `fixtures` and `labeledFixtures` are **public top-level exports**, not test-only helpers | drift output below lists both; `attrNames g.fixtures` ⇒ `["chain","cyclic","diamond","disconnected","serviceGraph","tree"]`, `attrNames g.labeledFixtures` ⇒ `["cyclic","poisoned","world"]` |
| `impactOf == dependentsOf` evaluates to `false` (Nix function comparison), so the alias cannot be confirmed by `==` | `lib/global.nix:impactOf`; `g.impactOf == g.dependentsOf` ⇒ `false`, while `(impactOf dia "d") == (dependentsOf dia "d")` ⇒ `true`. Test: `test-impactOf-uses-dependentsOf` (`ci/tests/global.nix`) |
| `coneRank` on a **cyclic** cone is an uncatchable infinite recursion (the `prelude.fix` recurrence becomes self-referential) | Read from `lib/global.nix:coneRank`'s precondition comment, **not exercised in this run** — exercising it would not terminate |

## Theory

Claimed in `README.md:743-757`, which tags each source *Implements* or *Informed by* inline, and restated in per-file header comments.

**Implements**

- **Arntzenius & Krishnaswami (2016), *Datafun: A Functional Datalog*** — monotone fixpoint iteration with convergence guarantees; `fixpoint` enforces the edge-count monotonicity guard, `seededFixpoint` is Datafun §9 semi-naive evaluation (`lib/fixpoint.nix:38`), and `dependents`/`dependentsOf` follow the reverse-query pattern (`lib/global.nix:dependents`/`dependentsOf`).
- **Tarjan (1983), *Data Structures and Network Algorithms*** — topological rank by longest incoming path; `coneRank` is `depth = 1 + max(depth of producers)` restricted to a supplied cone (`lib/global.nix:coneRank`).
- **Tarjan (1972), *Depth-First Search and Linear Graph Algorithms*** — pre-order discovery numbering as first-occurrence; `foldPreorder`/`expandPreorder`/`foldReach` fold a frame before its children, siblings in list order (`lib/preorder.nix:13-16`). `condensation` explicitly declines Tarjan's linear single-DFS: "Not Tarjan's linear O(V+E) single-DFS — its mutable stack/lowlink is out-of-substrate for pure Nix" (`lib/global.nix:condensation`, whose comment cites "Tarjan 1972 / Kosaraju for SCCs; Mokhov 2017 §4.6 Preorders and Equivalence Relations for the quotient-graph idiom").
- **Néron, Tolmach, Visser & Wachsmuth (2015), *A Theory of Name Resolution*** — `ancestorsOf` as P-edge resolution (§2.3), and the labeled query surface generalizing scope-graph reachability to arbitrary edge labels, with `visible`/`layers` generalizing Néron's D < I < P label order (`lib/query.nix:2-3`).
- **van Antwerpen, Poulsen, Rouvoet & Visser (2018), *Scopes as Types*** — the per-query label order with an end-of-path token; `order.endOfPath` (default `-1`) competes against the next label rank at word exhaustion (`lib/query.nix:135-141`).
- **Brzozowski (1964), *Derivatives of Regular Expressions*** — `deriv` and `nullable` are the classical functions, stepped alongside the graph walk (`lib/regex.nix:1-2`).
- **Owens, Reppy & Turon (2009), *Regular-expression Derivatives Re-examined*** — ACI normalization makes the derivative set finite and `stateKey` a sound seen-set key, which is what terminates the `all` mode's (node × derivative-state) product automaton on cyclic graphs (`lib/regex.nix:2-6`).

**Informed by** (README's own label)

- **Mokhov (2017), *Algebraic Graphs with Class*** — README marks the whole entry *Informed by* and scopes the borrowing precisely: the algebraic construction primitives inform the edge-map operations, which are "gen-graph's own contribution"; §4.5 supplies "only the equivalence-class *notion* of reduction" while `transitiveReduction` is gen-graph's own standard DAG algorithm; and "Transpose follows Mokhov 2017 §5.2 *Graph Transpose* directly." Code comments cite Mokhov at three further sites, all in `lib/global.nix`: the file-header entry for `transpose` and `lib/global.nix:transpose` itself ("Mokhov 2017 §5.2 Graph Transpose" — the law is that transpose flips the arguments of `connect` and leaves `overlay` unchanged, so direction is REVERSED, not erased), and `lib/global.nix:condensation` ("Mokhov 2017 §4.6 Preorders and Equivalence Relations for the quotient-graph idiom"). ★ The transpose coordinate is ADJUDICATED against the archived primary and the subsection title is quoted beside the number so it stays checkable; §4.5's "equivalence-class notion" wording is enumerated as claimed, not adjudicated. ★ `lib/order.nix` carries NO Mokhov citation: `topoOrder` is A. B. Kahn 1962 (README's own bibliography entry) and `phaseOrder`/`entry*` are the home-manager dag idiom expressed over it.
- **Kahn (1974), *The Semantics of a Simple Language for Parallel Programming*** — the lazy accessor pattern; §2.2.4 monotonicity. `lib/preorder.nix:23-27` makes the demand property load-bearing: `expandPreorder`'s `edges` read the *resolved* payload, so successors may be demand-generated, and a `seen0`-pruned frame is never forced.
- **Meijer, Fokkinga & Paterson (1991), *Functional Programming with Bananas, Lenses, Envelopes and Barbed Wire*** — `foldPreorder` has the shape of a hylomorphism: the visited-set coalgebra unfolds a possibly-cyclic graph into its finite DFS spanning forest, which `expand` folds (`lib/preorder.nix:17-22`).

**Checked invariant**: the library imports no `nixpkgs.lib` — enforced over `lib/**.nix` + root `flake.nix` + `default.nix` (not `ci/`) by `test-library-source-is-nixpkgs-lib-free` (`ci/tests/purity.nix`). The single dependency is gen-prelude (`flake.nix:6-8`); `lib/traverse.nix` takes not even that.

## Drift check

```sh
nix eval --json .#lib --apply 'l: { top = builtins.attrNames l; regex = builtins.attrNames l.regex; fixtures = builtins.attrNames l.fixtures; labeledFixtures = builtins.attrNames l.labeledFixtures; }'
```

Current output (verbatim):

```json
{"fixtures":["chain","cyclic","diamond","disconnected","serviceGraph","tree"],"labeledFixtures":["cyclic","poisoned","world"],"regex":["alt","any","deriv","empty","eps","lit","nullable","opt","parse","plus","seq","star","stateKey"],"top":["ancestorsOf","canReach","coScc","compose","condensation","coneRank","cyclePaths","cycles","dependents","dependentsFrontier","dependentsOf","differenceEdges","directDependents","directDependentsOf","entryAfter","entryAnywhere","entryBefore","entryBetween","expandPreorder","field","fields","fixpoint","fixtures","foldPreorder","foldReach","fromRegistry","impactOf","intersectEdges","labeledFixtures","labeledFrom","leaves","materialize","materializeParents","mkGraph","pathsBetween","phaseOrder","query","queryFold","reachableFrom","reachableWhere","regex","roots","seededFixpoint","select","selectEdges","selfReachable","topoOrder","transitiveClosure","transitiveReduction","transpose","unionEdges"]}
```

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with `working-directory: ci`, `.github/workflows/ci.yml:13,18`):

```sh
nix flake check ./ci
```
