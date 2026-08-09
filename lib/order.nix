# Ordering — the one ordering front door for the gen ecosystem, plus the
# home-manager-style DAG entry constructors (before/after) layered on top of it.
#
# THEORY: `topoOrder` is A. B. Kahn's algorithm (1962, "Topological sorting of large
# networks", CACM 5(11)) — indegree over the dependency relation, a ready set of
# indegree-zero nodes, and the residual-emptiness check for cycles. This is A. B. Kahn
# 1962, NOT Gilles Kahn 1974 (KPN, cited in preorder.nix for the lazy accessor pattern):
# a different author and a different result. `entry*`/`phaseOrder` are the home-manager
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
# performs exactly E decrements. The residual is min-extraction over the ready set, which a
# priority queue makes O(log m) at m live nodes — and pure Nix CAN express one. A persistent
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
# call PLUS `global.condensation`, and it runs only on a CYCLIC graph. NEITHER term may be
# quoted as the cost alone: which of the two is larger flips with the graph shape and with
# the allocation axis measured. Ordering succeeds or it throws; the expensive analysis is on
# the way out.
{ prelude }:
let
  global = import ./global.nix { inherit prelude; };

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
  topoOrder =
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
      # Reverse index — the pick's successors, the only indegrees a pick may touch. O(E).
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
            indeg = st.indeg // prelude.genAttrs succs (s: st.indeg.${s} - 1);
            newly = builtins.filter (s: indeg.${s} == 0) succs;
          in
          {
            inherit indeg;
            ready = insertAll (mergeH st.ready.l st.ready.r) newly;
            emitted = st.emitted ++ [ pick ];
          };

      # The loop-carried fields, for the driver to force at every step: `indeg` accumulates
      # `//` updates and `emitted` accumulates a list spine, and WHNF on the state record
      # reaches neither.
      #
      # WHNF on `ready` is enough, and that is a property of the heap rather than a shortcut.
      # A ready set the loop rebuilds lazily layers one thunk per step and overflows the C
      # stack when it is finally forced — a distinct abort from `max-call-depth`, and one the
      # array implementation was silently insured against because `builtins.sort` must force
      # every element to compare it. `mergeH` supplies that barrier structurally: reaching
      # WHNF runs the comparison at the root, which forces both operands' keys, and the rank
      # test forces both children to WHNF before the node is built. So a heap node in WHNF has
      # its children in WHNF, and forcing the root leaves no layer behind it.
      carried = st: builtins.seq st.indeg (builtins.seq st.ready (builtins.length st.emitted));

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
        indeg = indeg0;
        # Heapified by repeated insert, Θ(m log m). Not sorted first: the heap orders what it
        # holds, so a sort feeding it would be discarded work.
        ready = insertAll null (builtins.filter (k: indeg0.${k} == 0) keys);
        emitted = [ ];
      } keys;

      # The cycle report is SCC MEMBERSHIP, named by `cycles`/`condensation` rather than
      # read off the residual: every node in a cycle, grouped by its component, sorted
      # within each group. `cycles` is self-reachability, so a self-loop is reported as
      # the singleton it is — a component `condensation` alone cannot distinguish from an
      # acyclic node.
      keyAccessor = {
        nodes = keys;
        edges = k: depsOf.${k} or [ ];
      };
      cyclicKeys = global.cycles keyAccessor;
      sccOf = (global.condensation keyAccessor).sccOf;
      cycles = prelude.mapAttrsToList (_: g: map (k: nodeOf.${k}) g) (builtins.groupBy sccOf cyclicKeys);
    in
    if refusal != null then
      throw "gen-graph.topoOrder: ${refusal}"
    else if builtins.length final.emitted < builtins.length keys then
      {
        ok = false;
        inherit cycles;
      }
    else
      {
        ok = true;
        order = map (k: nodeOf.${k}) final.emitted;
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
    phaseOrder
    ;
}
