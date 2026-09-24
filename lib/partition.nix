# SCC partitioning — the one published door and the three arms behind it: two forward–backward
# arms and Tarjan's lowlink arm.
#
# THEORY. A strongly connected component is an equivalence class of the mutual-reachability
# relation (Tarjan 1972, Lemma 9), and the condensation is the QUOTIENT of the graph by that
# relation — Mokhov 2017 §4.6 Preorders and Equivalence Relations, the quotient-graph idiom. The quotient is ACYCLIC: a cycle among
# classes would make every class on it mutually reachable, i.e. one class. Every construction
# below rests on that fact, and the finisher is where it is spent.
#
# FORWARD–BACKWARD is the decomposition both arms share. For a pivot v,
#
#   SCC(v) = { v } ∪ ( reach(v) ∩ coreach(v) )
#
# which is the mutual-reachability definition read pointwise. Fleischer, Hendrickson & Pınar
# (2000, "On Identifying Strongly Connected Components in Parallel", IPDPS) is where that
# identity is developed into an ALGORITHM: one pivot's forward and backward sets cut the
# vertex set into pieces that can be solved independently of each other. `fbWork` is that
# development, iterated over a worklist rather than recursed in parallel. `fbNode` spends a
# pivot on EVERY node and does no cutting at all, which is why it carries no accumulator —
# it is the definition, not the algorithm built on it.
#
# TARJAN'S SINGLE DFS IS THE THIRD ARM, `lowlink`, AND IT IS ITERATED RATHER THAN RECURSED.
# Neither the mutable stack nor recursion rules it out. A persistent structure holds a stack
# and a lowlink map without mutation, the way this library's own ready set is a purely
# functional heap (`lib/order.nix`). Recursion is an obstruction only to the RECURSIVE
# formulation: STRONGCONNECT written as a self-applying DFS step is closed off twice over —
# ADR-0022 makes NON-RECURSIVE SCC detection a binding constraint, and the evaluator's
# call-depth ceiling ends a step that applies itself with an uncatchable `stack overflow;
# max-call-depth exceeded`, measured on this library at ~10^4 frames (AGENTS.md's
# frame-ceiling row) and again as `coneRank`'s descent (`lib/order.nix`, its driver). The DFS
# does not need that formulation: its call stack is data, so one `builtins.genericClosure`
# loop steps it, one edge or one pop per step, over a persistent map. That is `lowlink`
# below. Its cost is Θ((n + m) · log₈ n), not Tarjan's O(V + E): the log is the persistent
# map's, paid on each index read and write. The forward–backward arms ITERATE over a worklist
# too, and remain for the shapes where they are cheaper (README, *When each arm wins*).
#
# THE DOOR CARRIES THE DEFAULT, THE ARM CARRIES THE ALGORITHM — the pattern `lib/order.nix`
# landed for ordering, applied to the concern the same reasoning assigns to this library. A
# caller whose correctness depends on WHICH algorithm answers binds the arm by name; the
# door's default is a separate decision from any arm's identity.
#
# ── WHY THE ORDERING DOOR AND THIS ONE MAY REFERENCE EACH OTHER ──
# The finisher below calls the ordering ARM (through `coneRank`) on the CONDENSATION, and the
# ordering arm calls a partition ARM on its own cycle-report branch. That is not a circle at
# evaluation: the graph the finisher hands to the ordering arm is the quotient, which is
# acyclic, so that call never reaches the cycle-report branch and never re-enters a
# partitioner. Both directions bind ARMS rather than doors, so neither default can move the
# other's meaning.
{ prelude }:
let
  inherit (import ./key.nix)
    attrKey
    edgesAccessor
    identifier
    keyedAttrs
    notEdgeList
    renderId
    ;
  traverse = import ./traverse.nix;
  global = import ./global.nix { inherit prelude; };
  order = import ./order.nix { inherit prelude; };

  # THE PERSISTENT MAP the iterated DFSs below carry: a B-ary trie of ints over ORDINALS 0..n-1,
  # every cell 0 until set. `get` folds over the digits and `set` path-copies the spine, so each
  # costs Θ(log_B n); `set` forces every node it builds (ADR-0022). B = 8 was measured against 4,
  # 16 and 32 on calls, `list.elements` and wall time, and won at 20k and 100k. Shared by
  # `lowlink` (its index map) and `cyclePaths` (its witness walk's visited set).
  trieOf =
    n:
    let
      B = 8;
      digit = k: d: builtins.bitAnd (k / d) (B - 1);
      levels = builtins.length divs;
      divs = builtins.genericClosure {
        startSet = [ { key = 1; } ];
        operator = x: if x.key * B >= n then [ ] else [ { key = x.key * B; } ];
      };
      divsDown = builtins.genList (l: (builtins.elemAt divs (levels - 1 - l)).key) levels;
      force = l: builtins.foldl' (a: x: builtins.seq x a) l l;
    in
    {
      empty = builtins.foldl' (sub: _: builtins.genList (_: sub) B) 0 divsDown;
      get = t: k: builtins.foldl' (node: d: builtins.elemAt node (digit k d)) t divsDown;
      set =
        t: k: x:
        let
          spine = builtins.foldl' (
            acc: l: acc ++ [ (builtins.elemAt (builtins.elemAt acc l) (digit k (builtins.elemAt divsDown l))) ]
          ) [ t ] (builtins.genList (l: l) (levels - 1));
        in
        builtins.foldl' (
          child: l:
          let
            node = builtins.elemAt spine l;
            d = digit k (builtins.elemAt divsDown l);
          in
          force (builtins.genList (j: if j == d then child else builtins.elemAt node j) B)
        ) x (builtins.genList (l: levels - 1 - l) levels);
    };

  # A strict cons cell, and the walk that reads a cons list out as a list of cells, head first.
  cell = h: t: builtins.seq h (builtins.seq t { inherit h t; });
  conses =
    l:
    builtins.genericClosure {
      startSet =
        if l == null then
          [ ]
        else
          [
            {
              key = 0;
              c = l;
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

  # ── THE ARM-NEUTRAL FINISHER, AND IT IS PUBLISHED ──
  # Everything the door publishes beyond the tag map is a function of the tag map, so it is
  # computed HERE, from the partition, and never inside an arm. EVERY arm calls this one
  # binding — including `condensationClosure`, which lives in `lib/global.nix` and reaches it
  # by name — so "the arms return the same record" is a property of the CONSTRUCTION and not
  # of the cells that check it. An arm finishing its own record would agree with its siblings
  # exactly as long as someone kept the copies in step, which is agreement by maintenance.
  # It is exported for that reason rather than as a convenience.
  #
  # THE PRECONDITION IS THE CALLER'S: `tagOf` must be a tag map of an SCC PARTITION, total on
  # `nodes`. Hand it a map that is not one and the quotient it induces can be cyclic, and the
  # ordering pass below refuses that by name rather than answering. That is what makes the
  # published fields cost the same whichever arm produced the partition. It is also why no
  # PER-NODE measure is published: `fbNode` computes per-node reachability as its own work
  # and `fbWork` deliberately does not, so a per-node field would be free on one arm and a
  # tax on the other — and the arm it taxed would be the one kept because it does not pay
  # that price.
  #
  # PLAIN DATA, BY CONSTRUCTION. A published cross-library surface is read across a foreign
  # evaluation, where only strings, lists, integers and attrsets of those survive. So the
  # lookups are published as MAPS, not as the functions a same-evaluation caller would
  # prefer: a function's identity is minted by the build that made it and cannot cross. A
  # caller wanting a lookup builds one from the map on its own side.
  #
  # `depth` is the LONGEST PATH over the condensation DAG, and it is the only measure
  # published. Closure cardinality and the per-node and summed reach counts are all
  # determined by the partition, so a consumer derives whichever one its own cost model is
  # fitted over — and names its own domain at the point it derives it. Publishing one of
  # them here would decide that for every consumer; publishing the partition decides nothing
  # and loses nothing, because both arms must produce it to be partitioners at all.
  #
  # ★ THE DOMAIN IS CHECKED HERE, ONCE, FOR EVERY ARM: a CLOSED accessor, every target `edges`
  # returns a member of `nodes`. An edge to x ∉ `nodes` means `(nodes, edges)` is not a graph
  # (Tarjan 1972 §2: E is a set of pairs of V), so it has no SCC partition, and every field below
  # indexes `tagOf` by a target. The check is seq'd onto the record, so reading ANY field — `sccOf`
  # included — refuses by name under the arm's own name rather than answering for one arm and
  # aborting on another. Same refusal the ordering family gives a dangling target (`topoOrderCore`).
  condensationOf = finish "condensationOf";
  finish =
    who:
    { edges, nodes, ... }:
    tagOf:
    let
      e = edgesAccessor who edges;
      memberSet = keyedAttrs (map (identifier who) nodes) (_: true);
      # `nodes` is validated BEFORE any target is read: the scan below short-circuits on a
      # non-string target without forcing `memberSet`, so a non-string NODE with an edge would
      # otherwise be reported as a target outside `nodes`.
      closed = builtins.seq memberSet builtins.all (
        v:
        let
          es = e v;
        in
        if !builtins.isList es then
          throw (notEdgeList who v es)
        else
          builtins.all (d: builtins.isString d && memberSet ? ${attrKey d}) es
          || throw "gen-graph.${who}: edges ${renderId v} names a target outside `nodes`"
      ) nodes;
      membersOf = prelude.mapAttrs (_: es: builtins.sort builtins.lessThan (map (e: e.n) es)) (
        builtins.groupBy (e: attrKey e.r) (
          map (n: {
            r = tagOf.${attrKey n};
            n = n;
          }) nodes
        )
      );
      # ★ THE DISTINCT TAGS ARE READ OFF THE GROUPING, NOT UNIQUED OUT OF A LIST — and the
      # reason is that the grouping already carries the answer, not that a dedup would be
      # quadratic. `prelude.unique` is TWO-PATH: on an all-string list it dedups through a
      # `listToAttrs`/`sort` over first-occurrence indices, Θ(n) on the LIST axis and
      # Θ(n log n) in comparisons; the `foldl' (acc: x: if elem x acc then acc else acc ++
      # [ x ])` that is Θ(n²) on both survives only as the fallback for a non-string domain.
      # Tags are strings, so uniquing one tag per node would take the sorting path — a sort
      # over a set whose distinct members `membersOf` has already grouped, i.e. redundant work
      # rather than a quadratic. Same reading `coneRank` records for the same reason.
      tags = map (ms: tagOf.${attrKey (builtins.head ms)}) (builtins.attrValues membersOf);
      # Deduplicated the same way, and the targets come out SORTED rather than in accessor
      # order — so the condensation's edge lists are a function of the graph and not of the
      # order a caller's `edges` happens to enumerate.
      condEdges = keyedAttrs tags (
        r:
        builtins.filter (t: t != r) (
          builtins.attrValues (
            keyedAttrs (map (m: tagOf.${attrKey m}) (
              prelude.concatMap (
                m:
                (
                  let
                    es = e m;
                  in
                  if builtins.isList es then es else throw (notEdgeList "condensationOf" m es)
                )
              ) (membersOf.${attrKey r} or [ ])
            )) (t: t)
          )
        )
      );
      # ONE ordering pass over the quotient supplies BOTH published order-shaped fields, and
      # neither routes through a capped fixpoint. `coneRank` warms a memoized longest-path
      # recurrence along the ordering arm's order, so its rank map IS the longest-path DP and
      # its emitted order IS a reverse-topological order: a class that points at another has
      # a strictly greater rank, so it sorts strictly later. The quotient is acyclic, so the
      # cyclic-cone refusal below it is unreachable from here.
      ranked = order.coneRank { edges = r: condEdges.${attrKey r} or [ ]; } tags;
    in
    builtins.seq closed {
      reps = ranked.order;
      bottomUp = ranked.order;
      members = membersOf;
      sccs = map (r: membersOf.${attrKey r} or [ ]) ranked.order;
      sccOf = tagOf;
      inherit condEdges;
      depth = builtins.foldl' prelude.max 0 (prelude.attrValues ranked.depth);
    };

  # The component tag: its SMALLEST member. Two shipped consumers group their OUTPUT by the
  # tag and feed the grouping to an iteration in sorted key order, so the tag is not an
  # arbitrary witness — their emitted order is a function of which member is chosen. Both
  # arms therefore choose the same one, and the choice is part of the contract rather than an
  # implementation detail.
  tagOfMembers = members: builtins.head (builtins.sort builtins.lessThan members);

  # ── ARM: PER-NODE FORWARD–BACKWARD ──
  # Two `genericClosure` calls per node — the forward set from v, and the backward set from v
  # over the transposed accessor — intersected. NO ACCUMULATOR AND NO RECURSION: the whole arm
  # is `genAttrs` over the node set, so there is no loop-carried aggregate whose forcing could
  # be deferred and no self-application spending an evaluator frame per link. The two
  # constraints that cost the other arm a discipline hold here by construction.
  #
  # PRICE, ON THE RECORD RATHER THAN ABSORBED: the pivot is spent per NODE, so one large
  # component is walked once for every member it has. `fbWork` walks it once. That is the
  # whole reason both arms exist, and it is why neither refuses the other's input.
  #
  # `reachableFrom` excludes its own start, so the class is the intersection PLUS the pivot —
  # which is also what makes an acyclic node the singleton class it is, rather than the empty
  # one its own reach set would suggest.
  #
  # BOTH ACCESSORS ARE READ ONCE RATHER THAN AT EVERY VISIT (`traverse.hoistEdges`). This arm
  # spends 2n closures over exactly two accessors, so the per-visit wrapping is loop-invariant
  # across all of them: paying it once as Θ(n + E) per direction removes a factor of n from the
  # attrset axis, taking the dense reading from Θ(n³) to Θ(n²). The hoist is admissible here for
  # the reason it is inadmissible at a single-closure caller — the price is spread over 2n
  # traversals, not over one.
  nodeTags =
    accessor@{ edges, nodes, ... }:
    let
      rev = global.transpose accessor;
      succFwd = traverse.hoistEdges accessor;
      succBwd = traverse.hoistEdges rev;
      forward = keyedAttrs nodes (v: traverse.reachableVia succFwd v);
      backward = keyedAttrs nodes (v: prelude.genAttrs (traverse.reachableVia succBwd v) (_: true));
    in
    keyedAttrs nodes (
      v:
      let
        bv = backward.${attrKey v};
      in
      tagOfMembers (
        [ v ]
        ++ builtins.filter (
          u:
          bv
            ? ${
              if builtins.isString u && builtins.hasContext u then builtins.unsafeDiscardStringContext u else u
            }
        ) forward.${attrKey v}
      )
    );

  # ── ARM: WORKLIST FORWARD–BACKWARD ──
  # One forward–backward pass per COMPONENT rather than per node: a node already assigned is
  # skipped, and both passes are restricted to the still-unassigned set.
  #
  # THE RESTRICTION IS SOUND, and the argument is Fleischer–Hendrickson–Pınar's: a walk that
  # leaves the pivot's class and returns to it puts every node it passed through in that same
  # class, since each such node both reaches the pivot and is reached by it. So no member of
  # the pivot's class — and no node on any path witnessing that class — can have been
  # assigned by an earlier round, and cutting the assigned set away cannot cut a witness.
  #
  # THE ACCUMULATOR CANNOT CHAIN, AND THAT IS BY CONSTRUCTION RATHER THAN BY DISCIPLINE.
  # `builtins.foldl'` forces the accumulator only to weak head normal form, which for a record
  # is the record and not its fields, so a field written every round and read in none
  # accumulates one update thunk per component; forcing that chain at the end spends an
  # evaluator frame per link and ends in an abort no caller can catch. Here there is ONE
  # field, and the round's FIRST act is to read it — so the previous round's update is in
  # normal form before the current one begins, and at most one unforced update exists at any
  # moment. The two-field spelling, where the tag map is written but only the remaining set is
  # read, is the construction that does chain; it is reproduced as a live negative control in
  # `ci/bench/partition-ceiling.nix` so this claim is measured rather than asserted. Removing
  # the failure beats bounding it: nothing here refuses at a component count.
  #
  # ★ AND THIS ARM DOES NOT HOIST ITS ACCESSOR, though `fbNode` beside it does. The reason is the
  # MEMOIZATION's price against what this arm's rounds actually walk. `traverse.hoistEdges` builds
  # a whole-graph Θ(n) memo up front; `fbNode` spends it across 2n closures that each re-cover the
  # graph, but this arm's closures PARTITION it — each round walks a subgraph the previous rounds
  # have shrunk — so there is no second traversal over the same edges to spread that build cost
  # over. That is `dependentsOf`'s mechanism (pay for the graph, use part of it), and this is the
  # same negative cell one arm along. Measured 4.12x BETTER on one deep chain — the one shape whose
  # backward walk re-covers the whole unassigned tail every round, so the memo is spent many times
  # over — and 1.003–1.25x WORSE on `complete`, `fleet`, `wide`, `total` and `cycle`.
  #
  # ★ THE RESTRICTION ORDER IS NOT THE LEVER, and that is measured rather than assumed: an arm
  # that memoizes plain adjacency and applies the per-round restriction BEFORE wrapping recovers
  # none of the loss — worst of the three arms on `fleet` (108,603 sets against the shipped arm's
  # 103,803), and within 4 sets of the full hoist on `cycle` while BOTH memoizing arms sit ~2,400
  # above the shipped one. The penalty follows the memo, not the discard. So the arm stays as it
  # is. Both arms are kept in `ci/bench/cost-classes.nix` (`fbWork` against `fbWorkHoisted`) so
  # the trade is a reading rather than a recollection.
  workTags =
    accessor@{ edges, nodes, ... }:
    let
      rev = global.transpose accessor;
      e = edgesAccessor "fbWork" edges;
      step =
        acc: v:
        if acc.tags ? ${attrKey v} then
          acc
        else
          let
            live = id: !(acc.tags ? ${attrKey id});
            forward = keyedAttrs (traverse.reachableFrom {
              edges =
                id:
                builtins.filter live (
                  let
                    es = e id;
                  in
                  if builtins.isList es then es else throw (notEdgeList "fbWork" id es)
                );
            } v) (_: true);
            component = [
              v
            ]
            ++ builtins.filter (u: forward ? ${u}) (
              traverse.reachableFrom { edges = id: builtins.filter live (rev.edges id); } v
            );
            tag = tagOfMembers component;
          in
          {
            tags = acc.tags // keyedAttrs component (_: tag);
          };
    in
    (builtins.foldl' step { tags = { }; } nodes).tags;

  # ── ARM: TARJAN'S LOWLINK, ITERATED ──
  # Tarjan 1972's STRONGCONNECT: number vertices in DFS order, keep a stack of points, and pop a
  # component when a vertex's LOWLINK equals its own number (Lemma 12; Theorem 13 for the
  # procedure). One DFS, so every node and every edge is visited once.
  #
  # THE RECURSION IS DATA. The DFS call stack `cs` is a cons list of frames, each holding its
  # vertex, its successor list, the index of the next edge and its lowlink. One
  # `builtins.genericClosure` step does exactly one of four things — push a frame, examine one
  # edge, finish a frame (folding its lowlink into the parent's), or pop one member off the point
  # stack `ss` — so the loop runs O(n + m) steps. The code contains no recursion at all: every
  # loop is `genericClosure` or `foldl'`, the trie's included.
  #
  # THE INDEX MAP is a persistent 8-ary trie of ints over ORDINALS: 0 is unvisited, a positive
  # value is the DFS number while the vertex is on the point stack, −1 is assigned. `get` folds
  # over the digits, `set` path-copies the spine, so each costs Θ(log₈ n) — which is where the
  # arm's Θ((n + m) · log₈ n) comes from, and why its evaluation depth grows as Θ(log₈ n) (one
  # nesting per trie level inside a step) although nothing recurses. B = 8 was measured against
  # 4, 16 and 32 on calls, `list.elements` and wall time, and won at 20k and 100k.
  #
  # ORDINALS ARE KEY ORDER. Ordinal i is position i of the keyed node set's `attrNames`, so the
  # contract's tag — the SMALLEST member (`tagOfMembers`) — is the member of least ordinal,
  # tracked as an integer minimum during the pop with no string comparison. Tarjan names a
  # component by its ROOT; that is a different member whenever the DFS enters a component at a
  # member that is not its smallest, and `ci/tests/partition.nix`'s `lateentry` shape is the
  # fixture that tells the two apart. The tag is the caller's `nodes` entry, with its context.
  #
  # EVERY FIELD THE LOOP CARRIES IS FORCED EACH STEP, BY CONSTRUCTION (ADR-0022). Every record is
  # built by one of five strict constructors (`cell`, `frame`, `popping`, `comp`, `state`), each
  # of which `seq`s every field before returning it; `genericClosure` forces each new state to
  # read its `key`. So no field is ever an unforced thunk pointing into an earlier step, and the
  # property belongs to the constructors rather than to a list of `seq`s kept in step with them.
  #
  # ITS DOMAIN IS A CLOSED ACCESSOR. A target outside `nodes` is refused by name, as the ordering
  # family refuses a dangling target (`topoOrderCore`): an edge to x ∉ V means (V, E) is not a
  # graph, so it has no SCC partition. A `nodes` entry that is not a string is refused by name
  # too; it cannot be keyed.
  lowlinkTags =
    { edges, nodes, ... }:
    let
      e = edgesAccessor "lowlink" edges;
      byKey = keyedAttrs (map (identifier "lowlink") nodes) (v: v);
      names = builtins.attrNames byKey;
      verts = builtins.attrValues byKey;
      n = builtins.length names;
      ordOf = builtins.listToAttrs (
        builtins.genList (i: {
          name = builtins.elemAt names i;
          value = i;
        }) n
      );
      ordinal =
        from: w:
        if builtins.isString w && ordOf ? ${attrKey w} then
          ordOf.${attrKey w}
        else
          throw "gen-graph.lowlink: edges ${renderId from} names a target outside `nodes`";
      succOf =
        v:
        let
          id = builtins.elemAt verts v;
          es = e id;
        in
        if builtins.isList es then map (ordinal id) es else throw (notEdgeList "lowlink" id es);

      inherit (trieOf n) empty get set;
      frame =
        v: es: i: low:
        builtins.seq v (
          builtins.seq es (
            builtins.seq i (
              builtins.seq low {
                inherit
                  v
                  es
                  i
                  low
                  ;
              }
            )
          )
        );
      popping =
        root: min: ms:
        builtins.seq root (builtins.seq min (builtins.seq ms { inherit root min ms; }));
      comp = tag: ms: builtins.seq tag (builtins.seq ms { inherit tag ms; });
      state =
        key: map: next: cs: ss: r: pop: out:
        builtins.seq key (
          builtins.seq map (
            builtins.seq next (
              builtins.seq cs (
                builtins.seq ss (
                  builtins.seq r (
                    builtins.seq pop (
                      builtins.seq out {
                        inherit
                          key
                          map
                          next
                          cs
                          ss
                          r
                          pop
                          out
                          ;
                      }
                    )
                  )
                )
              )
            )
          )
        );

      push =
        s: cs: r: v:
        state (s.key + 1) (set s.map v s.next) (s.next + 1) (cell (frame v (succOf v) 0
          s.next
        ) cs) (cell v s.ss) r null s.out;

      step =
        s:
        if s.pop != null then
          let
            w = s.ss.h;
            p = s.pop;
            m = if w < p.min then w else p.min;
            ms = cell w p.ms;
          in
          state (s.key + 1) (set s.map w (-1)) s.next s.cs s.ss.t s.r (
            if w == p.root then null else popping p.root m ms
          ) (if w == p.root then cell (comp m ms) s.out else s.out)
        else if s.cs == null then
          if s.r >= n then
            null
          else if get s.map s.r != 0 then
            state (s.key + 1) s.map s.next null s.ss (s.r + 1) null s.out
          else
            push s null (s.r + 1) s.r
        else
          let
            f = s.cs.h;
          in
          if f.i < builtins.length f.es then
            let
              w = builtins.elemAt f.es f.i;
              mw = get s.map w;
              f' = frame f.v f.es (f.i + 1) (if mw > 0 && mw < f.low then mw else f.low);
            in
            if mw == 0 then
              push s (cell f' s.cs.t) s.r w
            else
              state (s.key + 1) s.map s.next (cell f' s.cs.t) s.ss s.r null s.out
          else
            let
              parent = s.cs.t;
            in
            state (s.key + 1) s.map s.next (
              if parent == null then
                null
              else
                cell (frame parent.h.v parent.h.es parent.h.i (
                  if f.low < parent.h.low then f.low else parent.h.low
                )) parent.t
            ) s.ss s.r (if f.low == get s.map f.v then popping f.v n null else null) s.out;

      run = builtins.genericClosure {
        startSet = [ (state 0 empty 1 null null 0 null null) ];
        operator =
          s:
          let
            s' = step s;
          in
          if s' == null then [ ] else [ s' ];
      };
      last = builtins.elemAt run (builtins.length run - 1);
    in
    builtins.listToAttrs (
      builtins.concatMap (
        x:
        map (y: {
          name = builtins.elemAt names y.c.h;
          value = builtins.elemAt verts x.c.h.tag;
        }) (conses x.c.h.ms)
      ) (conses last.out)
    );

  # ── THE ARMS, PUBLISHED BY NAME ──
  # Each is the finisher over one arm's tag map, so on a closed accessor the three differ in HOW
  # the partition is found and in nothing else a caller can observe. That is what makes them
  # complementary rather than ranked, and a caller that must have one of them can say so. All
  # three take the same input — a closed accessor, checked once in the finisher — and refuse
  # anything else under their own name.
  # `fbWork`'s tag is its component's smallest member as the BACKWARD pass returns it, and that
  # pass reads `transpose`, whose sources are text: so a representative (and `sccOf`) carrying
  # string context can come back as its text, depending on node order. `fbNode` keeps it.
  fbNode = accessor: finish "fbNode" accessor (nodeTags accessor);
  fbWork = accessor: finish "fbWork" accessor (workTags accessor);
  lowlink = accessor: finish "lowlink" accessor (lowlinkTags accessor);

  # ── THE PARTITION'S CONSUMERS: WHICH NODES LIE ON A CYCLE, AND ONE WALK PER CYCLIC COMPONENT ──
  # A node lies on a cycle iff its strongly connected component has two or more members, or it
  # has an edge to itself (Tarjan 1972, Lemma 9: the SCCs are the classes of mutual reachability,
  # and a singleton class is cyclic exactly when it carries a self-loop). So membership is read
  # off the partition, and the partition is the `lowlink` ARM by name, never the door — these
  # consumers read the tag map and nothing else. Cost is the arm's, Θ((n + m) · log₈ n), plus one
  # accessor read per node for the self-loop test. They moved here from `lib/global.nix` because
  # they are partition consumers now, as `coneRank` moved to the ordering family; the export set
  # is unchanged. Their DOMAIN is the arm's: a closed accessor, refused by name otherwise.
  cyclicOf =
    accessor@{ edges, nodes, ... }:
    let
      inherit (lowlink accessor) sccOf;
      e = edgesAccessor "cycles" edges;
      size = builtins.mapAttrs (_: builtins.length) (
        builtins.groupBy (k: attrKey sccOf.${k}) (builtins.attrNames sccOf)
      );
      onCycle = v: size.${attrKey sccOf.${attrKey v}} > 1 || builtins.elem v (e v);
    in
    {
      inherit sccOf;
      cyclic = builtins.sort builtins.lessThan (builtins.filter onCycle nodes);
    };
  cycles = accessor: (cyclicOf accessor).cyclic;

  # One representative simple cycle per cyclic component, as an ORDERED node list rotated to
  # begin at the component's smallest key; every consecutive pair is an edge, closing back on the
  # head. Acyclic input => [ ]. ONE per component, not all: enumerating every simple cycle is
  # Johnson 1975, exponential in its output, and deliberately not provided.
  #
  # THE WITNESS is the walk a depth-first search from the component's smallest member `u` finds:
  # take `u`'s first successor inside the component, `v`, then search from `v` for `u`, visiting
  # successors in `edges` order and never a node twice, restricted to the component. It is the
  # FIRST simple path from `v` to `u` in that order — the one `pathsBetween`'s enumeration yields
  # first, which this surface used to read off it — because a node a depth-first search has
  # finished without reaching `u` reaches `u` only through the search's current stack, so
  # re-entering it along another simple path cannot find `u` either. Leaving the component
  # cannot change the answer: a node outside it does not reach `u`. So the walk is the one this
  # surface always returned, found in one pass over the component rather than by enumerating
  # simple paths — which was exponential on a strongly connected random graph and refused any
  # cycle longer than `pathsBetween`'s depth cap.
  #
  # ITERATED, as `lowlink` is: the search's stack is a cons list of frames and its visited set a
  # persistent trie over the component's ordinals, stepped by one `genericClosure` loop whose every
  # record is built by a strict constructor (ADR-0022). Θ((|C| + m_C) · log₈ |C|) per component.
  cyclePaths =
    accessor@{ edges, nodes, ... }:
    let
      c = cyclicOf accessor;
      e = edgesAccessor "cyclePaths" edges;
      witness =
        members:
        let
          u = builtins.head (builtins.sort builtins.lessThan members);
          inC = keyedAttrs members (_: true);
          ks = builtins.attrNames inC;
          ordOf = builtins.listToAttrs (
            builtins.genList (i: {
              name = builtins.elemAt ks i;
              value = i;
            }) (builtins.length ks)
          );
          inherit (trieOf (builtins.length ks)) empty get set;
          succ = v: builtins.filter (w: inC ? ${attrKey w}) (e v);
          v0 = builtins.head (succ u);
          frame =
            v: es: i:
            builtins.seq v (builtins.seq es (builtins.seq i { inherit v es i; }));
          state =
            key: vis: cs: done:
            builtins.seq key (
              builtins.seq vis (
                builtins.seq cs (
                  builtins.seq done {
                    inherit
                      key
                      vis
                      cs
                      done
                      ;
                  }
                )
              )
            );
          step =
            s:
            let
              f = s.cs.h;
            in
            if f.i < builtins.length f.es then
              let
                w = builtins.elemAt f.es f.i;
                rest = cell (frame f.v f.es (f.i + 1)) s.cs.t;
              in
              if w == u then
                state (s.key + 1) s.vis rest true
              else if get s.vis ordOf.${attrKey w} != 0 then
                state (s.key + 1) s.vis rest false
              else
                state (s.key + 1) (set s.vis ordOf.${attrKey w} 1) (cell (frame w (succ w) 0) rest) false
            else
              state (s.key + 1) s.vis s.cs.t false;
          run = builtins.genericClosure {
            startSet = [ (state 0 (set empty ordOf.${attrKey v0} 1) (cell (frame v0 (succ v0) 0) null) false) ];
            operator = s: if s.done then [ ] else [ (step s) ];
          };
          stack = conses (builtins.elemAt run (builtins.length run - 1)).cs;
          depth = builtins.length stack;
        in
        if v0 == u then
          [ u ]
        else
          [ u ] ++ builtins.genList (i: (builtins.elemAt stack (depth - 1 - i)).c.h.v) depth;
    in
    map witness (
      prelude.mapAttrsToList (_: g: g) (builtins.groupBy (k: attrKey c.sccOf.${attrKey k}) c.cyclic)
    );

  # ── THE FRONT DOOR ──
  # The default is the `lowlink` arm, and the delegation is an IDENTITY rather than a wrapper,
  # which is the only spelling that cannot drift from what it delegates to. Changing the
  # default changes this line and nothing a caller of an arm by name depends on.
  #
  # The default sits on an arm with no accumulator whose forcing is deferred, no recursion and
  # no capped fixpoint, so the default path has no iteration cap to inherit and no refusal that
  # names something other than the caller's graph. Of the three arms it is the one whose cost
  # is Θ((n + m) · log₈ n) on every shape; the per-node arm it replaced is quadratic in the size
  # of one large component (README, *When each arm wins*). The door refuses an open accessor
  # under `lowlink`'s name, which is the one observable that says which arm it is bound to.
  condensation = lowlink;
in
{
  inherit
    condensation
    condensationOf
    cycles
    cyclePaths
    fbNode
    fbWork
    lowlink
    ;
}
