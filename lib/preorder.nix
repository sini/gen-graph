# Ordered, payload-carrying pre-order graph traversal — the DFS-preorder dual of
# the label-blind `genericClosure` surface in `traverse.nix`.
#
# `builtins.genericClosure` is C-level but BFS, single-keyed and payload-blind: it
# returns a SET in an unspecified visitation order, with one dedup key and no way to
# expose the traversed edge or carry a per-node projection. These combinators are the
# missing ORDERED, PAYLOAD-CARRYING, LABEL-EXPOSING analog — an explicit-stack DFS with a
# threaded visited set, which `genericClosure`'s own dedup structurally cannot express.
# `genericClosure` is still the LOOP (one element per DFS step, keyed by the step count,
# so its dedup never fires); the visited set, not the closure's done set, is what
# delegates the cycle-guard/dedup here, because the ORDER, the payload and the edge
# exposure are precisely the value the closure builtin lacks.
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
  inherit (import ./key.nix)
    attrKey
    badResult
    callable
    callableAt
    edgesAccessor
    notEdgeList
    retiredMaxDepth
    ;

  # ── THE RECURSION IS DATA (ADR-0022), so these walks have NO DEPTH OR FAN-OUT CEILING ──
  #
  # Every walk here is a `builtins.genericClosure` loop, the construction `partition.nix`'s
  # `lowlinkTags` already uses: one closure element per DFS action (pop an exhausted sibling
  # cursor, skip a visited frame, or expand one), the DFS stack an explicit cons list of
  # `{ cs; i; }` cursors, and every carried field `seq`'d by its constructor at each step.
  # `genericClosure` is an unbounded C-level loop that does not grow the evaluator stack, so no
  # evaluator ceiling is reached by DFS depth, by fan-out, or by the length of an accumulator
  # chain — measured to 200,000 on a chain and a star and 402,000 on a 2,000-deep spine of
  # 200-leaf nodes (den-hoag-2t0sj). With no ceiling there is no refusal to state (ADR-0032:
  # "owed where a real ceiling exists, and only there"), so `maxDepth` is RETIRED: each surface
  # still accepts it, and refuses it by name (`retiredMaxDepth`) rather than ignoring it
  # silently or meeting it with an uncatchable `unexpected argument` (ADR-0025 item 1). The
  # refusal gates the whole result, so reading any one field of it refuses. `null` is absence.
  #
  # ★ THE PRICE, RECORDED (ADR-0033's form). An INFINITE demand-generated graph — an unbounded
  # stream of distinct keys, or `null`-keyed frames that generate forever — now DIVERGES rather
  # than refusing: the walk runs until the evaluator is killed (measured: a prototype still
  # running at 20.6 GB after 134 s, deaf to SIGTERM, where the old depth cap refused it in
  # 0.12 s). The ground is not precedent: from any finite prefix it is undecidable whether a
  # demand-generated graph is infinite, so every guard that refuses an infinite graph also
  # refuses some finite graph past a bound, which makes it a cost cap, and ADR-0032 forbids one.
  # The domain precondition is therefore stated instead: the reachable key set is finite, and
  # `null`-keyed frames terminate by finite authored structure. `reachableFrom` and every other
  # `genericClosure` surface of this library carry the same precondition.
  #
  # ★ STRICTNESS, A CONTRACT: the accumulator is forced to WHNF AT EVERY FRAME, whether or not
  # the caller reads it (ADR-0022's per-round forced accumulator; ADR-0032's "a strict read
  # forces the field it reads and no other" is why it is WHNF only). So `visited` is no longer
  # independent of `acc`: an `acc` that throws at WHNF — or, for `foldReach`, a `project` or
  # `itemKey` that throws, since those build its accumulator — refuses the whole call, including
  # a caller who reads `.visited` alone, and the refusal surfaces at the frame where it arises
  # (so with two bad inputs the one reported can differ from the older recursive walk's). The
  # seed `acc` is forced even when `roots = [ ]`. A caller whose `acc` carries a LAZILY CHAINED
  # field (`{ xs = a.xs ++ [ f ]; }`) keeps that chain's own ceiling where the caller reads the
  # field, after the walk has returned: that is the caller's ceiling, not an unguarded one here.
  #
  # ── THE VISITED SET: Bentley & Saxe's logarithmic method (1980, *Decomposable Searching
  #    Problems I: Static-to-Dynamic Transformation*) over native attrsets.
  #
  # Extending an attrset by `//` copies it, so a set grown one key per step copies Θ(n²) values.
  # Membership is a DECOMPOSABLE searching problem (x ∈ A ∪ B iff x ∈ A ∨ x ∈ B), so the static
  # structure — Nix's own attrset, a sorted array the evaluator searches — becomes dynamic: `buf`
  # holds at most B keys, and a full `buf` is carried into `lv` as a binary counter, level i
  # empty or holding B·2ⁱ keys. Each key is then copied O(log(n/B)) times. Membership is two
  # primops, `buf ? k` and `catAttrs k lv`, with no lambda per level; the set is materialised
  # once, at the end, by one `listToAttrs`. The caller's seed set is CONSULTED, never copied.
  # Lowlink's trie does not fit: it indexes ordinals of a closed node list, and these frames are
  # demand-generated (Kahn, the header), so the key domain is open.
  #
  # B = 32 is a constant, not a parameter: it moves only the constant factor. Measured on
  # `expandPreorder` over a chain, 1k → 8k (den-hoag-2t0sj gate, T3), copies per doubling and
  # copies / calls at 8k: B=8 ×2.34–2.27, 75,595 / 358,135; B=32 ×2.33–2.26, 70,117 / 327,703;
  # B=64 ×2.28–2.23, 77,494 / 323,463; B=128 ×2.18–2.17, 101,049 / 321,579. 32 sits at the copy
  # minimum and on the call plateau.
  #
  # COST, per walk over n frames and m edges: Θ(n + m) closure steps plus the caller's own
  # `expand` work; Θ(n log(n/B)) values copied into the set (measured copies ÷ n·log₂(n/32):
  # 1.17, 1.10, 1.08 at 1k, 8k, 64k); `list.elements` ≈ ×2 per doubling (`push`'s `out ++ [ l ]`
  # is O(levels²) per carry); function calls ≈ 3× the old recursion's, the price of two steps
  # per node and the strict constructors. PEAK MEMORY grows with the values copied, because
  # `genericClosure` retains every state until it returns (`expandPreorder`: 269 MB peak RSS on
  # a 64k chain, 798 MB on the 402k spine). The copy figures are Nix 2.34's: its `//` layers a small right-hand side
  # rather than copying (32 single-key inserts copy 79 values, not 528), so `buf //` copying
  # "at most B" is an upper bound and the measured copies come from the level merges. The
  # bound is amortised: one carry cascade copies Θ(n) in a single step.
  levels = rec {
    B = 32;
    mk =
      buf: nb: lv:
      builtins.seq buf (builtins.seq nb (builtins.seq lv { inherit buf nb lv; }));
    empty = mk { } 0 [ ];
    member = s: k: s.buf ? ${k} || builtins.catAttrs k s.lv != [ ];
    push =
      lv: carry:
      let
        r =
          builtins.foldl'
            (
              st: l:
              if st.carry == null then
                st // { out = st.out ++ [ l ]; }
              else if l == { } then
                {
                  carry = null;
                  out = st.out ++ [ st.carry ];
                }
              else
                {
                  carry = l // st.carry;
                  out = st.out ++ [ { } ];
                }
            )
            {
              inherit carry;
              out = [ ];
            }
            lv;
        out = if r.carry == null then r.out else r.out ++ [ r.carry ];
      in
      builtins.foldl' (a: x: builtins.seq x a) out out;
    insert =
      s: k:
      let
        buf = s.buf // {
          ${k} = true;
        };
      in
      if s.nb + 1 < B then mk buf (s.nb + 1) s.lv else mk { } 0 (push s.lv buf);
    toAttrs =
      s:
      builtins.listToAttrs (
        builtins.concatMap (
          l:
          map (name: {
            inherit name;
            value = true;
          }) (builtins.attrNames l)
        ) ([ s.buf ] ++ s.lv)
      );
  };

  # A witness list is built as `{ h; t; }` cons cells, O(1) per step with `h` left unforced (so
  # `emit`/`resolve` fire when the caller forces an element, as before), and read out ONCE here:
  # one `genericClosure` over the cells (`partition.nix`'s `conses` idiom), reversed by
  # `genList`, so no `++` chains across steps.
  consList =
    c:
    let
      items = builtins.genericClosure {
        startSet =
          if c == null then
            [ ]
          else
            [
              {
                key = 0;
                inherit c;
              }
            ];
        operator =
          x:
          if x.c.t == null then
            [ ]
          else
            [
              {
                key = x.key + 1;
                c = x.c.t;
              }
            ];
      };
      n = builtins.length items;
    in
    builtins.genList (i: (builtins.elemAt items (n - 1 - i)).c.h) n;

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
  #    `maxDepth` is retired (the header) and refused by name; `surface` is the name that
  #    refusal and every caller-function refusal carry, so a specialization written outside
  #    this library (a framework's `forwardExpand`) names itself.
  foldPreorder =
    {
      roots,
      key,
      expand,
      acc,
      visited ? { },
      maxDepth ? null,
      surface ? "foldPreorder",
    }:
    let
      kf = callableAt surface "key" "a node id (a string) or null" key;
      ex = callableAt surface "expand" "{ acc; children ? [ ]; }" expand;
      cell = h: t: builtins.seq h (builtins.seq t { inherit h t; });
      at = cs: i: builtins.seq i { inherit cs i; };
      state =
        key: acc: marks: stk:
        builtins.seq key (
          builtins.seq acc (
            builtins.seq marks (
              builtins.seq stk {
                inherit
                  key
                  acc
                  marks
                  stk
                  ;
              }
            )
          )
        );
      step =
        s:
        if s.stk == null then
          null
        else
          let
            top = s.stk.h;
          in
          if top.i >= builtins.length top.cs then
            state (s.key + 1) s.acc s.marks s.stk.t
          else
            let
              frame = builtins.elemAt top.cs top.i;
              rest = cell (at top.cs (top.i + 1)) s.stk.t;
              k =
                let
                  k0 = kf frame;
                in
                if k0 == null || builtins.isString k0 then
                  k0
                else
                  badResult surface "key" "on a frame" "a node id (a string) or null" k0;
            in
            if k != null && (visited ? ${attrKey k} || levels.member s.marks (attrKey k)) then
              state (s.key + 1) s.acc s.marks rest
            else
              let
                r =
                  let
                    h = ex s.acc;
                    r0 = h frame;
                  in
                  if !(builtins.isFunction h || callable h) then
                    badResult surface "expand" "on the accumulator"
                      "a function from a frame to { acc; children ? [ ]; }"
                      h
                  else if builtins.isAttrs r0 && r0 ? acc then
                    r0
                  else
                    badResult surface "expand" "on a frame" "{ acc; children ? [ ]; }" r0;
                cs =
                  let
                    c = r.children or [ ];
                  in
                  if builtins.isList c then c else badResult surface "expand" "on a frame" "children as a list" c;
              in
              state (s.key + 1) r.acc (if k == null then s.marks else levels.insert s.marks (attrKey k)) (
                if cs == [ ] then rest else cell (at cs 0) rest
              );
      run = builtins.genericClosure {
        startSet = [ (state 0 acc levels.empty (cell (at roots 0) null)) ];
        operator =
          s:
          let
            s' = step s;
          in
          if s' == null then [ ] else [ s' ];
      };
      last = builtins.elemAt run (builtins.length run - 1);
    in
    if maxDepth != null then
      throw (retiredMaxDepth surface)
    else
      {
        inherit (last) acc;
        visited = visited // levels.toAttrs last.marks;
      };

  # ── expandPreorder: payload-carrying DFS-preorder closure (the attempt-1 framework's
  #    `forwardExpand`, frozen per ADR-0002).
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
      maxDepth ? null,
    }:
    let
      e = edgesAccessor "expandPreorder" edges;
      # applied, never read: a door each, and `emit`'s first application must return a function
      rs = callableAt "expandPreorder" "resolve" "a payload" resolve;
      em = callableAt "expandPreorder" "emit" "a function from a payload to a witness" emit;
      r = foldPreorder {
        inherit roots key;
        surface = "expandPreorder";
        visited = seen0;
        acc = null;
        expand =
          nodes: frame:
          let
            payload = rs frame;
          in
          {
            acc = {
              h = (
                let
                  h = em frame;
                in
                if builtins.isFunction h || callable h then
                  h payload
                else
                  badResult "expandPreorder" "emit" "on a frame" "a function from a payload to a witness" h
              );
              t = nodes;
            };
            children = (
              let
                es = e payload;
              in
              if builtins.isList es then es else throw (notEdgeList "expandPreorder" payload es)
            );
          };
      };
    in
    if maxDepth != null then
      throw (retiredMaxDepth "expandPreorder")
    else
      {
        nodes = nodes0 ++ consList r.acc;
        seen = r.visited;
      };

  # ── foldReach: labeled, suppression-aware, transitive reach fold (the attempt-1
  #    framework's `reach`, frozen per ADR-0002).
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
      maxDepth ? null,
    }:
    let
      ik = callableAt "foldReach" "itemKey" "a string or null" itemKey;
      pj = callableAt "foldReach" "project" "a list of items" project;
      addItem =
        st: item:
        let
          k =
            let
              k0 = ik item;
            in
            if k0 == null || builtins.isString k0 then
              k0
            else
              badResult "foldReach" "itemKey" "on an item" "a string or null" k0;
        in
        if k != null && (seen0 ? ${attrKey k} || levels.member st.seen (attrKey k)) then
          st
        else
          let
            seen = if k == null then st.seen else levels.insert st.seen (attrKey k);
            nodes = {
              h = item;
              t = st.nodes;
            };
          in
          builtins.seq seen (builtins.seq nodes { inherit seen nodes; });
      e = edgesAccessor "foldReach" edges;
      r = foldPreorder {
        inherit roots;
        surface = "foldReach";
        key = target;
        visited = visited0;
        acc = {
          seen = levels.empty;
          nodes = null;
        };
        expand = st: edge: {
          acc = prelude.foldl' addItem st (
            let
              xs = pj edge;
            in
            if builtins.isList xs then xs else badResult "foldReach" "project" "on an edge" "a list of items" xs
          );
          children = (
            let
              es = e (target edge);
            in
            if builtins.isList es then es else throw (notEdgeList "foldReach" (target edge) es)
          );
        };
      };
    in
    if maxDepth != null then
      throw (retiredMaxDepth "foldReach")
    else
      {
        seen = seen0 // levels.toAttrs r.acc.seen;
        nodes = nodes0 ++ consList r.acc.nodes;
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
