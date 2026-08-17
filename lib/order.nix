# Ordering — the one ordering front door for the gen ecosystem, plus the
# home-manager-style DAG entry constructors (before/after) layered on top of it.
#
# THEORY: `topoOrder` is A. B. Kahn's algorithm (1962, "Topological sorting of large
# networks", CACM 5(11)) — indegree over the dependency relation, a ready set of
# indegree-zero nodes, and the residual-emptiness check for cycles. This is A. B. Kahn
# 1962, NOT Gilles Kahn 1974 (KPN, cited in preorder.nix for the lazy accessor pattern):
# a different author and a different result. That algorithm is ALSO exported under its own
# name, `topoOrderKahn`: `topoOrder` is the door, the arm is the algorithm, and a caller
# whose correctness depends on which algorithm answers binds the arm (see its comment). `entry*`/`phaseOrder` are the home-manager
# dag idiom (generalized strings-with-deps) expressed over it, absorbing what
# gen-dispatch's dag.nix used to own so gen-dispatch can be the pure dispatch STEP.
#
# EDGE DIRECTION, stated once and shared by every surface in this library:
# `edges u ∋ v` means "u DEPENDS ON v" (consumer → producer). An ordering is therefore
# producers-first: a node is emitted only after everything it depends on. `coneRank`,
# `condensation.bottomUp`, `dependentsOf` and `reachableFrom` all read the accessor this
# way, and callers that build their own accessor (gen-vars) do too.
#
# COST: building the reverse index and the indegree map is O(n + E) via groupBy; the loop
# performs exactly E decrements. What the loop ALLOCATES is a separate question from what it
# computes, and in a language whose only aggregate update is a whole-value copy it is the
# larger one: a step that appends to a vector or updates an attrset pays the size of the
# whole thing. Both loop-carried aggregates are therefore held in shapes that pay their
# UPDATE rather than their SIZE — the emitted sequence as a numerical representation and the
# indegree map as a residue over a rebuilt base, each argued where it is built below.
# The residual is min-extraction over the ready set, which a priority queue makes O(log m) at
# m live nodes — and pure Nix CAN express one. A persistent
# priority queue with O(log m) worst-case merge and delete-min does not require mutation:
# leftist heaps (Crane 1972; Knuth, TAOCP vol. 3 §5.2.3), skew heaps (Sleator & Tarjan 1986)
# and pairing heaps (Fredman, Sedgewick, Sleator & Tarjan 1986) are all purely functional,
# and Okasaki (*Purely Functional Data Structures*, 1998, §3.1) takes exactly this substrate
# restriction as its subject. The ready set here is a leftist heap, so the loop's ready-set
# term is Θ(n log n); holding it as a sorted array instead costs Θ(n²), because every arrival
# rebuilds the unconsumed residue and re-sorts it. ★ The absence of a mutable heap is also
# the reason `condensation` gives for not being Tarjan's algorithm (`lib/global.nix`); it is
# not a bound on either surface, and that justification is NOT re-derived here.
# The floor: emitting the ready set in min-key order under a caller-supplied comparator sorts
# that set, so the loop inherits the comparison-sorting bound of Ω(m log m) comparisons. The
# heap attains it, and no comparison-based container beats it without changing the contract.
# The loop is driven by a bounded iteration over the key list, so its EVALUATOR FRAME cost
# is constant in n — a self-applying step spends one frame per node, which caps ordering at
# the interpreter's call depth with an abort no caller can catch. Cost is the only bound on
# the ordering surface; there is no size at which it declines.
# The CYCLE path is deliberately not derived from the Kahn residual — a residual knows
# only THAT nodes went unemitted, not which cycles they form — so it costs a `global.cycles`
# call PLUS a PARTITION call, and it runs only on a CYCLIC graph. The partition it spends is
# `partition.fbNode`, the forward–backward arm, bound by name below: it is NOT the closure
# construction, and the difference is the whole cost story here. Measured at n = 200
# (`ci/bench/cost-classes.nix`, arms `cycles` / `fbNode` / `topoOrder`): on `cycle` the guard
# is 41,403 `list.elements` against the partition's 364,817, and on `complete` 160,003
# against 1,038,617 — the partition is the larger term on both shapes and on all three axes
# at that size, and the report as a whole is EXPONENT 2.00 on `list` and `nrLookups`, fitted
# over k = 25/50/100/200 on `cycle`; `sets` is approaching 2.00 from below (1.88 over the
# last pair) rather than sitting at it. Do not quote either term as the cost alone.
# ★ THE SURFACE THAT IS SUPER-QUADRATIC IS THE CLOSURE, AND IT IS NOT ON THIS PATH: reaching
# the same partition through `condensationClosure` instead is exponent 3.00 on `list` over the
# same k, and 3.00 on `sets` with `nrLookups` approaching 3.00 from below (2.85 over the last
# pair) — the three axes now agree on the class, where they once disagreed by two exponents
# and a single-axis budget could certify the path as quadratic. At k = 200 that is 48,641,421
# against this path's 406,205, a factor of 120. A cost claim about ordering-on-a-cycle that
# cites the closure is citing a surface this door stopped calling.
# Ordering succeeds or it REPORTS: `topoOrder` returns `ok = false` with the cycles on a cyclic
# graph and does not throw for one — `phaseOrder` is the layer that throws. The expensive
# analysis is on the way out either way.
{ prelude }:
let
  global = import ./global.nix { inherit prelude; };
  partition = import ./partition.nix { inherit prelude; };

  entryBetween = before: after: { inherit before after; };
  entryAnywhere = entryBetween [ ] [ ];
  entryAfter = after: entryBetween [ ] after;
  entryBefore = before: entryBetween before [ ];

  # topoOrder { nodes; edges; keyOf ? id; lessThan ? builtins.lessThan }
  #   => { ok = true; order = [ node ]; } | { ok = false; cycles = [ [ node ] ]; }
  #
  # NON-THROWING on a cycle: both migrating consumers build their own diagnostic from the
  # cycle set (gen-pipe names the channels and the operators; gen-edge names the
  # (target, channel) chain), so a front door that throws first denies them the material.
  # `phaseOrder` below is the throwing convenience layer for callers that want one.
  #
  # `keyOf` projects a node to its STRING identity, which is also its tie-break key. It
  # admits node values that are not themselves strings — gen-edge orders edge RECORDS by
  # a canonical sort key — and it is what makes the tie-break caller-supplied: ordering
  # incomparable nodes by a frozen key is what makes an ordering a pure function of the
  # node SET rather than of the input permutation. `lessThan` orders those keys, so a
  # caller wanting a different tie-break over the same identities supplies it there.
  #
  # `lessThan` must be a STRICT TOTAL ORDER on distinct keys — a PRECONDITION, and the one
  # place this library documents a requirement instead of refusing by name. The ready set is
  # a heap, and a heap is not stable, so a comparator that is not a strict total order can
  # separate this ordering from the one a stable whole-array sort would produce. Keys are
  # distinct by construction (`collisions` below refuses the rest). A guard is not available
  # at an acceptable cost: establishing totality of a caller-supplied comparator means
  # exercising it on every pair, Ω(m²) comparisons — asymptotically worse than the quadratic
  # the heap removes, and paid on every call including the overwhelming majority whose
  # comparator is `builtins.lessThan`. Recorded with its reason so it is not re-proposed as a
  # missing check.
  #
  # A `keyOf` output that is not a string, two nodes sharing a key, and an edge naming a
  # node outside `nodes` are all REFUSALS BY NAME. Each would otherwise reach `genAttrs`
  # or the indegree map and either abort with a type error that `tryEval` cannot catch,
  # or — worse — silently merge two nodes / report a phantom cycle.
  #
  # ── THE ARM, PUBLISHED BY NAME ──
  # This binding is the ordering ARM — A. B. Kahn 1962, the algorithm the header names —
  # and it is exported under its own name beside the front door, which today delegates to
  # it and to nothing else. The name is not decoration. A caller that must have THIS
  # algorithm cannot express that requirement through a front door whose default is a
  # separate decision, and `coneRank` is such a caller: it warms its memo map in a
  # topological order, so if it took that order from the front door, a default answering
  # with the rank recurrence would make the rank recurrence call itself. Binding the arm by
  # name is non-circular whatever the door defaults to.
  #
  # The door keeps the door's obligations — a default lives there, and a selection between
  # arms would be expressed there. The arm keeps the algorithm's: whoever calls
  # `topoOrderKahn` gets indegrees, a ready set and the residual cycle check, by name.
  topoOrderKahn =
    {
      nodes,
      edges,
      keyOf ? (node: node),
      lessThan ? builtins.lessThan,
    }:
    let
      keyed = prelude.imap0 (i: node: {
        inherit i node;
        key = keyOf node;
      }) nodes;
      keys = map (k: k.key) keyed;

      # ── refusals, in the order that makes each one's own check safe to run ──
      # `builtins.isString` first: every later check indexes an attrset by the key, and a
      # non-string attribute name is the uncatchable abort this whole guard exists for.
      nonString = builtins.filter (k: !builtins.isString k.key) keyed;
      keySet = prelude.genAttrs keys (_: true);
      byKey = builtins.groupBy (k: k.key) keyed;
      collisions = builtins.filter (g: builtins.length g > 1) (prelude.mapAttrsToList (_: g: g) byKey);
      nodeOf = prelude.mapAttrs (_: g: (builtins.head g).node) byKey;
      rawDepsOf = prelude.genAttrs keys (k: map keyOf (edges nodeOf.${k}));
      dangling = builtins.filter (d: !(builtins.isString d) || !(keySet ? ${d})) (
        prelude.concatMap (k: rawDepsOf.${k}) keys
      );

      refusal =
        if nonString != [ ] then
          let
            bad = builtins.head nonString;
          in
          "keyOf returned a non-string key (type ${builtins.typeOf bad.key}) for the node at "
          + "index ${toString bad.i}; ordering keys must be strings"
        else if collisions != [ ] then
          let
            g = builtins.head collisions;
          in
          "key ${builtins.toJSON (builtins.head g).key} names ${toString (builtins.length g)} nodes "
          + "(indices ${builtins.toJSON (map (k: k.i) g)}); ordering keys must be unique"
        else if dangling != [ ] then
          let
            d = builtins.head dangling;
          in
          "edge target ${
            if builtins.isString d then builtins.toJSON d else "of type ${builtins.typeOf d}"
          } is not in nodes"
        else
          null;

      # ── Kahn 1962 ──
      # An edge SET, so a repeated dependency counts once: `genAttrs` collapses duplicate
      # names, and an indegree that counts an arc the decrement only pays once would
      # never reach zero.
      depsOf = prelude.mapAttrs (_: ds: builtins.attrNames (prelude.genAttrs ds (_: true))) rawDepsOf;
      # Reverse index — the pick's successors, the only indegrees a pick may touch.
      # Θ(|keys| + E): the concatMap visits every key, so a key with no deps still costs its visit.
      dependentsOf = prelude.mapAttrs (_: es: map (e: e.value) es) (
        builtins.groupBy (e: e.name) (
          prelude.concatMap (
            k:
            map (d: {
              name = d;
              value = k;
            }) depsOf.${k}
          ) keys
        )
      );

      indeg0 = prelude.mapAttrs (_: ds: builtins.length ds) depsOf;
      nodeCount = builtins.length keys;

      # ── the ready set: a leftist heap ──
      # `null | { k; l; r; rank; }`, where `rank` is the length of the right spine and the
      # LEFTIST INVARIANT is `rank l >= rank r` at every node, which bounds that spine at
      # O(log m). `mergeH` walks the two right spines and rebuilds them, so merge — and with
      # it insert (merge against a singleton) and delete-min (merge the root's two children)
      # — is O(log m) worst case. Crane 1972; Knuth, TAOCP vol. 3 §5.2.3; Okasaki, *Purely
      # Functional Data Structures* 1998 §3.1.
      #
      # Immutability is paid in PATH COPYING, not in asymptotics: no node is overwritten, so
      # each merge allocates one attrset per node on the spine walk it rebuilds, and n
      # inserts with n delete-mins allocate Θ(n log n) attrsets. That is the trade — Θ(n log n)
      # on the set axis for the Θ(n²) list allocation a rebuilt-and-re-sorted array pays. It
      # is an achieved upper bound, not a proven optimum.
      rankOf = h: if h == null then 0 else h.rank;
      mergeH =
        a: b:
        if a == null then
          b
        else if b == null then
          a
        else if lessThan b.k a.k then
          mergeH b a
        else
          let
            r = mergeH a.r b;
            rl = rankOf a.l;
            rr = rankOf r;
          in
          if rl >= rr then
            {
              inherit (a) k;
              l = a.l;
              r = r;
              rank = rr + 1;
            }
          else
            {
              inherit (a) k;
              l = r;
              r = a.l;
              rank = rl + 1;
            };
      singleton = k: {
        inherit k;
        l = null;
        r = null;
        rank = 1;
      };
      insertAll = builtins.foldl' (h: k: mergeH h (singleton k));

      # ── the emitted sequence: a numerical representation ──
      # A Nix list is a VECTOR, so `emitted ++ [ pick ]` allocates a fresh k-element vector at
      # step k and recording an answer of size n costs Θ(n²). Prepending is not an escape —
      # `[ pick ] ++ emitted` copies exactly the same k+1 elements — and neither is a cons
      # chain, which trades the copy for an O(k) walk at every read. There is no O(1) append
      # in the substrate to reach for, so the accumulator has to stop being ONE list.
      #
      # THEORY: a NUMERICAL REPRESENTATION (Okasaki, *Purely Functional Data Structures* 1998
      # §9.1; §9.2.1 builds binary random-access lists from exactly this correspondence). The
      # sequence is held as RUNS whose lengths are the binary representation of the number of
      # nodes emitted, newest run first. Appending is then the INCREMENT of a binary counter:
      # prepend a one-element run, then carry while the low bit is set, each carry
      # concatenating the two equal-length runs at the front. An element is copied once per
      # carry it survives and no element survives more than ⌊log₂ n⌋ of them, so the loop
      # allocates Θ(n log n) in place of Θ(n²). The carry reads the COUNTER rather than
      # measuring the runs, which is the representation's whole point — the number is the
      # shape — and it is why the count is loop-carried rather than recovered at the end.
      # ★ The untouched runs are carried over by `tail`/`++`, which copy element POINTERS, and
      # NOT by a `genList` of `elemAt` — which allocates the same number of list cells but
      # makes each carried run a fresh indirection onto the previous list. Those indirections
      # compose: a run untouched for k carries is an `elemAt` chain k deep, and forcing it at
      # the end descends that chain, one evaluator frame per link. So the `genList` spelling of
      # this same function aborts with `error: stack overflow; max-call-depth exceeded` on a
      # chain of 8,000 nodes while returning correctly at 4,000. The bound is the evaluator's
      # CALL-DEPTH COUNTER, not the C stack, and the way to tell is to raise it: under
      # `--option max-call-depth 100000000` that same spelling returns correctly at 8,000,
      # 12,000 and 20,000, which an exhausted C stack would not do. The cost axis is identical
      # between the two spellings; only the sharing is.
      mergeRuns = rs: [ (builtins.elemAt rs 1 ++ builtins.head rs) ] ++ builtins.tail (builtins.tail rs);
      carryRuns = c: rs: if c - 2 * (c / 2) == 1 then carryRuns (c / 2) (mergeRuns rs) else rs;
      pushRun =
        c: rs: x:
        carryRuns c ([ [ x ] ] ++ rs);
      # Runs are newest-first and each run holds its own elements in emission order, so the
      # sequence is the runs reversed and concatenated — one pass over ⌊log₂ n⌋ + 1 runs.
      flushRuns =
        rs:
        let
          m = builtins.length rs;
        in
        prelude.concatLists (builtins.genList (i: builtins.elemAt rs (m - 1 - i)) m);

      # ── the indegree map: a residue over a base that is rebuilt, not rewritten ──
      # `indeg // genAttrs succs …` copies the WHOLE map at every step: Θ(n) allocated to
      # record |succs| decrements, Θ(n²) over the loop, and the map is n wide whether or not
      # the step touches two entries. The map is therefore split in two — a `base` that is not
      # rewritten, and a `residue` carrying only the nodes whose count has been decremented
      # and has NOT yet reached zero. A node enters the residue when one of its dependencies
      # is emitted and leaves it when its last one is, so where every indegree is one the
      # residue is empty at every step and the loop allocates nothing for it at all. A read is
      # the residue first and the base behind it.
      #
      # The residue alone is not enough, and the shape that breaks it is ordinary: a graph
      # that satisfies many nodes PARTIALLY and leaves them waiting carries a wide residue for
      # many steps, which is the same quadratic in a smaller font. So the residue is folded
      # back into the base — AMORTIZED REBUILDING (Overmars, *The Design of Dynamic Data
      # Structures*, 1983; Bentley & Saxe 1980 for the static-to-dynamic decomposition it
      # generalizes) — once carrying it has cost about what rebuilding costs. A residue `w`
      # wide costs ~w per step and took ~w steps to reach that width, so `w² ≥ n` is the point
      # where the two meet; that comparison IS the trigger, and no tuning constant enters,
      # because the balance is derived from the two costs rather than picked.
      #
      # ★ Amortized bounds do not survive PERSISTENT re-use of a structure's old versions —
      # Okasaki 1998 §5 makes that the objection to naive amortization in this setting. The
      # bound holds here because the loop is a fold: `iterateBounded` threads one state, every
      # version is consumed exactly once, and no step reaches back to an earlier one.
      #
      # The pick is the heap's root, which IS the minimum key under `lessThan`, so the emitted
      # order is the same greedy min-key sequence a sorted array consumed by cursor produces —
      # the keys are distinct, so that minimum is unique and the two agree element for element.
      step =
        st:
        if st.ready == null then
          st
        else
          let
            pick = st.ready.k;
            succs = dependentsOf.${pick} or [ ];
            # Read each loop-carried field once per step rather than once per successor.
            base = st.base;
            residue = st.residue;
            dropped = prelude.genAttrs succs (s: (residue.${s} or base.${s}) - 1);
            newly = builtins.filter (s: dropped.${s} == 0) succs;
            waiting = builtins.filter (s: dropped.${s} != 0) succs;
            entering = builtins.filter (s: !(residue ? ${s})) waiting;
            satisfied = builtins.filter (s: residue ? ${s}) newly;
            # The residue's width EXACTLY, maintained incrementally: `entering` is what this
            # step adds to the residue and `satisfied` what it removes, the two are disjoint,
            # and nothing else changes the key set — so the count needs no pass over the
            # residue. That is the point of maintaining it rather than asking: the obvious
            # spelling, `length (attrNames residue)`, is O(w) per step, which is exactly the
            # cost the residue exists to avoid. The exact count costs one membership test per
            # node the step decrements, i.e. O(E) over the whole loop.
            #
            # ★ It must count DISTINCT NODES and not DECREMENTS, and the difference is not a
            # rounding error. The trigger prices the residue's WIDTH: a residue `w` wide costs
            # ~w to carry per step AND took ~w steps to reach that width, which is what makes
            # `w² ≥ n` the point where carrying and rebuilding meet. Counting decrements
            # reaches the same number in ~w/d steps at out-degree d, so the rebuild's Θ(n)
            # amortizes against a d-th of the work the derivation assumed and folds fire with
            # no warrant. Measured on three shapes built to separate the two counts, one arm
            # against the other with only this line different: where every waiting node is
            # decremented exactly once the two are BIT-IDENTICAL on both allocation axes and
            # the exact count costs `n` extra lookups, nothing more; where each node waits on
            # eight producers the decrement count costs +4.8% / +8.4% / +15.3% of
            # `sets.elements` at n = 1,000 / 4,000 / 16,000, climbing with n; and on a driver
            # chain whose waiters are re-decremented at every step it moves the `sets`
            # exponent from 1.49 — E-linear, the floor for that shape — to 1.90, a factor of
            # 5.15 at n = 4,000, which is enough to put that shape BEHIND the whole-map copy
            # this residue replaced. PRODUCER: those three shapes are in no arm of
            # `ci/bench/cost-classes.nix`; they are recorded with the remedy spec in
            # `den-architecture`, `specs/2026-08-09-gen-graph-accumulator-remedies-spec.md`.
            width = st.width + builtins.length entering - builtins.length satisfied;
            fold = width * width >= nodeCount;
          in
          {
            # ★ The two branches build DIFFERENT THINGS, and neither builds the other's. A
            # fold discards the residue, so on a shape that folds at every step — a total
            # order does — spelling this as "rebuild the residue, then throw it away" pays a
            # `removeAttrs` over the whole residue per step for a value nothing reads. The
            # fold absorbs `dropped` directly instead, and it may: `dropped` carries the new
            # count for every successor, `residue` the older partial counts for everything
            # else, and a node left at zero is one whose dependencies are all emitted, so it
            # is never decremented again and the zero is never read.
            base = if fold then base // residue // dropped else base;
            residue =
              if fold then
                { }
              else if waiting == [ ] && satisfied == [ ] then
                residue
              else
                removeAttrs (residue // prelude.genAttrs waiting (s: dropped.${s})) satisfied;
            width = if fold then 0 else width;
            ready = insertAll (mergeH st.ready.l st.ready.r) newly;
            emitted = pushRun st.count st.emitted pick;
            count = st.count + 1;
          };

      # The loop-carried fields, for the driver to force at every step: WHNF on the state
      # record reaches none of them, and every one of them accumulates. `base` and `residue`
      # accumulate `//` and `removeAttrs`; `width` and `count` accumulate arithmetic; the runs
      # accumulate a chain of pending carries. ★ The last of those is not covered by forcing
      # the count, and the difference is an abort rather than a slowdown: with `count` forced
      # and the runs left alone, `deepSeq` over the answer dies with `error: stack overflow;
      # max-call-depth exceeded` on a chain of 2,000 nodes, because the carries are one
      # `mergeRuns` thunk deep per step. `builtins.length` on the runs forces the spine each
      # step, which is what keeps that chain one carry deep instead of n.
      #
      # WHNF on `ready` is enough, and that is a property of the heap rather than a shortcut.
      # A ready set the loop rebuilds lazily layers one thunk per step and overflows the C
      # stack when it is finally forced — a distinct abort from `max-call-depth`, and one the
      # array implementation was silently insured against because `builtins.sort` must force
      # every element to compare it. `mergeH` supplies that barrier structurally: reaching
      # WHNF runs the comparison at the root, which forces both operands' keys, and the rank
      # test forces both children to WHNF before the node is built. So a heap node in WHNF has
      # its children in WHNF, and forcing the root leaves no layer behind it.
      carried =
        st:
        builtins.seq st.base (
          builtins.seq st.residue (
            builtins.seq st.width (builtins.seq st.ready (builtins.seq st.count (builtins.length st.emitted)))
          )
        );

      # The loop is DRIVEN, not recursed. A step that applies itself costs one evaluator frame
      # per node — Nix does not reuse the frame of a tail call — so the descent depth is the
      # node count and ordering a large graph aborts with a stack overflow that `tryEval`
      # cannot contain; a bounded iteration's frame cost is constant in n. `keys` is the bound
      # on two counts: it has exactly the right length, and it is already materialized, so the
      # driver allocates nothing. n steps suffice — each productive step emits exactly one
      # node, `emitted` draws distinct keys from `keys`, and the step is the identity once the
      # ready set is exhausted, so every surplus step idles. A cyclic graph emits fewer than n
      # and the residual check below reads that unchanged.
      final = prelude.iterateBounded carried step {
        base = indeg0;
        residue = { };
        width = 0;
        # Heapified by repeated insert, Θ(m log m). Not sorted first: the heap orders what it
        # holds, so a sort feeding it would be discarded work.
        ready = insertAll null (builtins.filter (k: indeg0.${k} == 0) keys);
        emitted = [ ];
        count = 0;
      } keys;

      # The cycle report is SCC MEMBERSHIP, named by `cycles` and by a partition arm rather
      # than read off the residual: every node in a cycle, grouped by its component, sorted
      # within each group. `cycles` is self-reachability, so a self-loop is reported as
      # the singleton it is — a component the partition alone cannot distinguish from an
      # acyclic node.
      #
      # ★ THE PARTITION ARM IS BOUND BY NAME, never the partition front door — the same rule
      # `coneRank` follows for this door. The door's own default finishes its result with an
      # ordering pass, so an ordering arm reading the door would be ordering through a
      # surface that orders through it. Binding the arm is non-circular whatever either
      # door defaults to, and this consumer needs only the tag map.
      keyAccessor = {
        nodes = keys;
        edges = k: depsOf.${k} or [ ];
      };
      cyclicKeys = global.cycles keyAccessor;
      sccOf = (partition.fbNode keyAccessor).sccOf;
      cycles = prelude.mapAttrsToList (_: g: map (k: nodeOf.${k}) g) (
        builtins.groupBy (k: sccOf.${k}) cyclicKeys
      );
    in
    if refusal != null then
      throw "gen-graph.topoOrder: ${refusal}"
    else if final.count < nodeCount then
      {
        ok = false;
        inherit cycles;
      }
    else
      {
        ok = true;
        order = map (k: nodeOf.${k}) (flushRuns final.emitted);
      };

  # The FRONT DOOR. Today the ecosystem's one ordering has one arm, so the door IS that
  # arm: the delegation is an identity rather than a wrapper, which is the only spelling
  # that cannot drift from what it delegates to. A second arm changes this line and nothing
  # a caller of `topoOrderKahn` depends on.
  topoOrder = topoOrderKahn;

  # Cone-local producers-first rank: depth id = 1 + max(depth of in-cone producers).
  # O(|cone| + edges_in_cone) via prelude.fix memoization; NOT whole-graph condensation.
  # RTD 1983 topological enumeration restricted to a dependent cone.
  #
  # ── WHY THERE IS A DRIVER ──
  # The recurrence memoizes, which is what makes it linear, and memoization is also what
  # made it a DESCENT: reading the deepest node first walks the whole chain one evaluator
  # frame per link, and the interpreter's call-depth counter ends that walk with a
  # `stack overflow; max-call-depth exceeded` no caller can catch. Measured on the shipped
  # surface: `.order` returns at a 3,997-node chain and aborts at 3,998, and a whole-map
  # `.depth` read is clean to 32,000 on a chain whose keys ascend with depth while dying
  # between 1,999 and 2,000 on the SAME chain with the edges reversed — nothing changed but
  # the orientation, because `genAttrs` forces in sorted key order and that order is
  # topological in one direction and anti-topological in the other. The ceiling was never a
  # property of the accessor; it was a property of the ORDER the map was forced in.
  #
  # So the map is forced in a topological order taken in-library, and the descent flattens:
  # every node's producers are already forced when it is reached, so each entry costs one
  # frame instead of a chain of them. No ceiling found to 32,000 on `chain` or on
  # `deepwide` (`ci/bench/cone-ceiling.sh`), so per the ordering law this surface states
  # that and refuses nothing at a size. The recurrence, the memo and the `(depth, id)` sort
  # are untouched — the emitted order is identical element for element, which is the
  # oracle the remediation is held to, and it is why this is a removal rather than a
  # re-implementation. The price is one ordering pass, filed in `ci/bench/cost-classes.nix`
  # (arm `coneRank`) rather than accepted silently.
  #
  # ★ THE DRIVER IS THE ARM, BY NAME. `topoOrderKahn`, never the front door: if the door's
  # default ever becomes the rank recurrence, a `coneRank` warming from the door would be
  # the rank recurrence calling itself. Binding the arm is non-circular either way.
  #
  # ★★ THE VERDICT IS CONSULTED BEFORE THE MEMO MAP IS ENTERED, and that ordering is the
  # requirement — not merely that a driver exists. A cyclic cone makes the recurrence
  # self-referential, so the first re-entry of a thunk fires the black-hole detector: an
  # uncatchable `infinite recursion encountered`, reached after traversing the cycle exactly
  # once and therefore long before any bound. Measured: the same construction with the
  # driver COMPUTED but the memo read first aborts exactly that way, while reading the
  # verdict first refuses by name. An implementer who keeps the driver and moves the read
  # ahead of it has the remedy nominally in place and the black hole back.
  #
  # The refusal is therefore a BY-PRODUCT of the construction rather than a guard bolted on:
  # the ordering call that supplies the warming order is the same call that reports the
  # cycle, and it names it. Two consumers were answering this precondition two different
  # ways — one guarding by hand, one documenting it and not guarding — and neither had to.
  coneRank =
    accessor: cone:
    let
      coneSet = prelude.genAttrs cone (_: true);
      inConeProducers = id: builtins.filter (d: coneSet ? ${d}) (accessor.edges id);

      # The driver ranges over the DISTINCT ids: the memo map is keyed by id, so a repeated
      # cone entry is one memo cell and one warming step, and ordering keys must be unique
      # or the arm refuses the duplicate by name. `cone` itself is left alone — `order`
      # sorts what the caller handed over, as it always did.
      # ★ The distinct ids come from `coneSet`, which is already built. `prelude.unique` is
      # TWO-PATH: ids are strings, so a dedup here would take its sorting path and cost Θ(n)
      # on the LIST axis — 36,003 list elements, exactly 9n + 3, on 4,000 distinct strings,
      # against 16,016,001 on that same fixture for the `foldl'`/`elem` fallback the
      # non-string domain still takes, both measured. So a dedup here is no longer a
      # quadratic; it is a sort over a set the membership map already holds, which is
      # redundant work rather than a cost class. The ceiling this arm was removing was a depth
      # problem in either case. Reading the keys off the membership set is the same answer for
      # the cost of the `attrNames` list.
      driver = topoOrderKahn {
        nodes = builtins.attrNames coneSet;
        edges = inConeProducers;
      };

      # prelude.fix binds `depth` once, so each node's depth is forced at most once
      # (a plain recursive `let` would re-expand shared producers, blowing up to
      # exponential) — this is what delivers the O(|cone| + edges_in_cone) bound.
      depth = prelude.fix (
        d:
        prelude.genAttrs cone (
          id:
          let
            ps = inConeProducers id;
          in
          if ps == [ ] then 0 else 1 + prelude.foldl' (m: p: prelude.max m d.${p}) 0 ps
        )
      );

      # `builtins.foldl'` forces its accumulator at every step, so each step forces exactly
      # one memo cell, in the driver's order, and the fold carries no aggregate of its own:
      # iterative, no accumulator, no recursion added.
      warmed = builtins.foldl' (acc: id: builtins.seq depth.${id} acc) true driver.order;
      # Every read of the map goes through the warming pass, so no caller can reach an
      # unwarmed cell by reading `depth` directly.
      warmDepth = builtins.seq warmed depth;

      order = builtins.sort (
        a: b: if warmDepth.${a} == warmDepth.${b} then a < b else warmDepth.${a} < warmDepth.${b}
      ) cone;
    in
    if !driver.ok then
      throw "gen-graph.coneRank: cyclic cone has no producers-first rank; cycles ${builtins.toJSON driver.cycles}"
    else
      {
        inherit order;
        depth = warmDepth;
      };

  # after=[d] on n => n depends on d (edge n->d); before=[t] on n => t depends on n
  # (edge t->n). Both readings are the library direction stated in the header, so the
  # order comes straight off the front door with nothing to compensate for.
  phaseOrder =
    entries:
    let
      names = builtins.attrNames entries;
      arcs = prelude.concatMap (
        n:
        map (d: {
          from = n;
          to = d;
        }) (entries.${n}.after or [ ])
        ++ map (t: {
          from = t;
          to = n;
        }) (entries.${n}.before or [ ])
      ) names;
      grouped = builtins.groupBy (x: x.from) arcs;
      result = topoOrder {
        nodes = names;
        edges = id: map (x: x.to) (grouped.${id} or [ ]);
      };
    in
    # Throw-on-cycle preserves the contract gen-dispatch's dag.nix had.
    if result.ok then
      result.order
    else
      throw "gen-graph.phaseOrder: cyclic ordering constraints: ${builtins.toJSON result.cycles}";
in
{
  inherit
    entryAnywhere
    entryAfter
    entryBefore
    entryBetween
    topoOrder
    topoOrderKahn
    phaseOrder
    coneRank
    ;
}
