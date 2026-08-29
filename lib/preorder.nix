# Ordered, payload-carrying pre-order graph traversal — the DFS-preorder dual of
# the label-blind `genericClosure` surface in `traverse.nix`.
#
# `builtins.genericClosure` is C-level but BFS, single-keyed and payload-blind: it
# returns a SET in an unspecified visitation order, with one dedup key and no way to
# expose the traversed edge or carry a per-node projection. These combinators are the
# missing ORDERED, PAYLOAD-CARRYING, LABEL-EXPOSING analog — a manual DFS with a
# threaded visited attrset (the `pathsBetween` / `query.nix` `queryPaths` precedent),
# which `genericClosure` structurally cannot express. The visited attrset (not
# `genericClosure`) is what delegates the cycle-guard/dedup here, because the ORDER,
# the payload and the edge exposure are precisely the value the closure builtin lacks.
#
# Tarjan 1972 (*Depth-First Search and Linear Graph Algorithms*): the traversal is
#   DFS pre-order — a frame is folded BEFORE its children, siblings in list order, and
#   each frame is visited at most once (first occurrence wins) via a visited set keyed
#   by `key frame`. First-occurrence is Tarjan's pre-order discovery numbering.
# Meijer, Fokkinga & Paterson 1991 (*Functional Programming with Bananas, Lenses,
#   Envelopes and Barbed Wire*): `foldPreorder` is a HYLOMORPHISM — the visited-set
#   coalgebra unfolds the (possibly cyclic) graph into its finite DFS spanning forest,
#   which `expand` folds (catamorphism) into the accumulator. `expandPreorder` and
#   `foldReach` are that hylomorphism with the accumulator specialized to an ordered
#   witness list.
# Kahn 1974 (*The Semantics of a Simple Language for Parallel Programming*): edges are
#   demand-driven — `expand`/`resolve` force a frame ONLY when the traversal reaches it,
#   so a frame's successors may be lazily/demand-generated (they need not exist until
#   the frame is resolved, e.g. a parametric node invoked with context). A pre-seeded
#   visited key prunes that frame's whole subtree WITHOUT forcing it.
{ prelude }:
let
  # ── THE DEPTH CEILING, NAMED RATHER THAN REMOVED ──
  #
  # `foldPreorder.go` below is SELF-RECURSIVE — a frame's children are folded inside that
  # frame's own call — so the evaluator's call depth is the traversal's DFS DEPTH, and past
  # the evaluator's own `max-call-depth` the abort is `stack overflow; max-call-depth
  # exceeded`: an ABORT, not a throw, which `builtins.tryEval` cannot observe. Measured on a
  # bare chain probe at `374b0ad`, all three exported surfaces here: returns at depth 4,993,
  # aborts at 4,994 (≈2 evaluator frames per node against the 10,000 default).
  #
  # ★ THE CEILING IS NOT REMOVABLE HERE, WHICH IS WHY THIS IS A REFUSAL. The iterative
  # rewrite that removed `coneRank.order`'s ceiling bounded its loop by a materialized node
  # list (`prelude.iterateBounded` over `keys`), and this fold HAS NO SUCH LIST: `edges` is
  # demand-generated, a frame's successors need not exist until it is resolved (Kahn 1974,
  # the header), so there is no length to fold over. The only unbounded loop Nix offers
  # instead is self-recursion, and the evaluator has NO tail-call elimination — measured,
  # same instrument: a tail-recursive counter at 200,000 aborts with the same signature while
  # the same expression at 100 returns. A worklist rewrite would therefore trade a ceiling on
  # DFS DEPTH for one on ITERATION COUNT, which is strictly worse: the `deepwide` shape
  # returns today at every probed size precisely because its depth caps below the boundary
  # while its node count does not.
  #
  # So the cap is STATED and sits below the evaluator's, which is what makes the refusal
  # arrive first and be catchable (ADR-0009's fourth amendment: every exported ordering
  # surface refuses BY NAME at its ceiling; ADR-0032: owed where a real ceiling exists, and
  # only there). 4,000 leaves ~20% of the measured boundary as headroom for the CALLER's own
  # frames — the boundary is a property of the whole measuring expression, not of this
  # surface, so a caller nested deeper reaches it sooner and lowers `maxDepth` to match,
  # while one calling from the top may raise it.
  defaultMaxDepth = 4000;

  # The refusal names the SURFACE THE CALLER CALLED, not this shared core — same discipline
  # as `fixpoint.closureOf`, which takes its caller's name for exactly this reason. Unlike
  # that one it is NOT asserted against an enumeration: `foldPreorder` is a general primitive
  # whose specializations are written outside this library too (den-hoag's `forwardExpand`),
  # and such a caller naming itself is the point rather than a hole.
  depthRefusal =
    surface: cap:
    "gen-graph.${surface}: DFS depth exceeded the stated cap of ${toString cap}. This fold is self-recursive, so the evaluator's call depth IS the traversal's DFS depth; past the evaluator's own max-call-depth the failure is an uncatchable abort, and this cap sits below it so the refusal arrives first and `builtins.tryEval` can observe it. Raise `maxDepth` where the caller's own stack leaves room for it, or lower it where the caller is itself nested deep.";

  # ── foldPreorder: THE primitive. A pre-order DFS fold over an accessor-described
  #    graph, threading a caller-owned accumulator and a first-occurrence visited set.
  #
  #    `key frame` is the cycle-guard / first-occurrence key. A `null` key is NEVER
  #    guarded — such a frame is always expanded (an anonymous/keyless node that
  #    terminates by finite authored structure, not by the visited set).
  #    `expand acc frame -> { acc; children ? [ ] }` folds THIS frame into the
  #    accumulator (pre-order: `expand` sees `acc` before any child does) and yields
  #    its child frames, in list order. `visited` seeds the guard set — a pre-seeded
  #    key drop-prunes that frame's subtree (Kahn demand: it is never forced). Returns
  #    the final `{ acc; visited }`.
  #
  #    All three named traversals below are five-line specializations of this fold
  #    (the audit's "one combinator parameterized by projection + seen").
  #
  #    `maxDepth` is the stated depth ceiling above; `surface` is the name its refusal
  #    carries. Roots sit at depth 1, so a chain of exactly `maxDepth` nodes traverses and
  #    one node deeper refuses.
  foldPreorder =
    {
      roots,
      key,
      expand,
      acc,
      visited ? { },
      maxDepth ? defaultMaxDepth,
      surface ? "foldPreorder",
    }:
    let
      go =
        depth: state: frame:
        let
          k = key frame;
        in
        # ★ THE GUARD SITS AFTER THE VISITED CHECK, and that is load-bearing rather than
        # incidental: an already-visited frame returns without descending, so it can never
        # be what reaches the evaluator's ceiling, and refusing on one would change the
        # answer for graphs that never approach the cap. Depth grows only through frames
        # this fold actually expands, so the first such frame past the cap is the refusal.
        if k != null && state.visited ? ${k} then
          state
        else if depth > maxDepth then
          throw (depthRefusal surface maxDepth)
        else
          let
            marked = if k == null then state.visited else state.visited // { ${k} = true; };
            r = expand state.acc frame;
          in
          prelude.foldl' (go (depth + 1)) {
            acc = r.acc;
            visited = marked;
          } (r.children or [ ]);
    in
    prelude.foldl' (go 1) { inherit acc visited; } roots;

  # ── expandPreorder: payload-carrying DFS-preorder closure (den-hoag `forwardExpand`).
  #    Folds `emit frame (resolve frame)` in first-occurrence pre-order into an ordered
  #    witness list. `resolve` is the (possibly parametric) node force; `edges` reads
  #    the RESOLVED payload's successors, so `edges` may be demand-generated — a
  #    parametric node's children exist only after `resolve` invokes it (Kahn 1974).
  #    ONE key set: `key frame` both cycle-guards and dedups (each frame is one
  #    witness). `seen0` seeds that set (drop-pruning), `nodes0` seeds the witness list.
  #    `emit` defaults to the payload itself. Returns `{ nodes; seen }`.
  expandPreorder =
    {
      roots,
      key,
      edges,
      resolve ? (frame: frame),
      emit ? (_frame: payload: payload),
      seen0 ? { },
      nodes0 ? [ ],
      maxDepth ? defaultMaxDepth,
    }:
    let
      r = foldPreorder {
        inherit roots key maxDepth;
        surface = "expandPreorder";
        visited = seen0;
        acc = nodes0;
        expand =
          nodes: frame:
          let
            payload = resolve frame;
          in
          {
            acc = nodes ++ [ (emit frame payload) ];
            children = edges payload;
          };
      };
    in
    {
      nodes = r.acc;
      seen = r.visited;
    };

  # ── foldReach: labeled, suppression-aware, transitive reach fold (den-hoag `reach`).
  #    Folds over labeled EDGES, each carrying a `target` vertex and a projection label
  #    (e.g. a class filter). `project edge -> [ item ]` is the per-edge content
  #    projection — the whole edge is EXPOSED, so the projection can slice the target's
  #    content by the edge's label (one edge → many items). Negative-edge SUPPRESSION is
  #    expressed by the `edges` accessor itself (it returns a vertex's edges MINUS the
  #    suppressed ones), so the fold is suppression-aware by construction — nothing here
  #    needs to know the suppression rule. TWO key sets, because one vertex projects many
  #    items: `target edge` cycle-guards the vertex DFS (`visited0`), while `itemKey item`
  #    first-occurrence-dedups the witness list ACROSS vertices (`seen0`; a `null` item
  #    key is never deduped — always kept, the conservative NULL-KEEP direction).
  #    `nodes0` seeds the witness list. Returns `{ nodes; seen; visited }`.
  foldReach =
    {
      roots,
      edges,
      target,
      project,
      itemKey,
      visited0 ? { },
      seen0 ? { },
      nodes0 ? [ ],
      maxDepth ? defaultMaxDepth,
    }:
    let
      addItem =
        st: item:
        let
          k = itemKey item;
        in
        if k != null && st.seen ? ${k} then
          st
        else
          {
            seen = if k == null then st.seen else st.seen // { ${k} = true; };
            nodes = st.nodes ++ [ item ];
          };
      r = foldPreorder {
        inherit roots maxDepth;
        surface = "foldReach";
        key = target;
        visited = visited0;
        acc = {
          seen = seen0;
          nodes = nodes0;
        };
        expand = st: edge: {
          acc = prelude.foldl' addItem st (project edge);
          children = edges (target edge);
        };
      };
    in
    {
      inherit (r.acc) seen nodes;
      visited = r.visited;
    };
in
{
  inherit
    foldPreorder
    expandPreorder
    foldReach
    ;
}
