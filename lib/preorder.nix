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
  foldPreorder =
    {
      roots,
      key,
      expand,
      acc,
      visited ? { },
    }:
    let
      go =
        state: frame:
        let
          k = key frame;
        in
        if k != null && state.visited ? ${k} then
          state
        else
          let
            marked = if k == null then state.visited else state.visited // { ${k} = true; };
            r = expand state.acc frame;
          in
          prelude.foldl' go {
            acc = r.acc;
            visited = marked;
          } (r.children or [ ]);
    in
    prelude.foldl' go { inherit acc visited; } roots;

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
    }:
    let
      r = foldPreorder {
        inherit roots key;
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
        inherit roots;
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
