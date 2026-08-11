# SCC partitioning — the one published door and the forward–backward arms behind it.
#
# THEORY. A strongly connected component is an equivalence class of the mutual-reachability
# relation (Tarjan 1972; Kosaraju's two-pass formulation of the same partition), and the
# condensation is the QUOTIENT of the graph by that relation — Mokhov 2017 §4.6 Preorders and
# Equivalence Relations, the quotient-graph idiom. The quotient is ACYCLIC: a cycle among
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
# NEITHER ARM IS TARJAN'S LINEAR SINGLE-DFS. Its mutable stack and lowlink are out of
# substrate for pure Nix — the reason `condensationClosure` (`lib/global.nix`) already gives
# for not being it either.
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
  traverse = import ./traverse.nix;
  global = import ./global.nix { inherit prelude; };
  order = import ./order.nix { inherit prelude; };

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
  condensationOf =
    { edges, nodes, ... }:
    tagOf:
    let
      membersOf = prelude.mapAttrs (_: es: builtins.sort builtins.lessThan (map (e: e.n) es)) (
        builtins.groupBy (e: e.r) (
          map (n: {
            r = tagOf.${n};
            n = n;
          }) nodes
        )
      );
      # ★ THE DISTINCT TAGS ARE READ OFF THE GROUPING, NOT UNIQUED OUT OF A LIST.
      # `prelude.unique` is `foldl' (acc: x: if elem x acc then acc else acc ++ [ x ])`, which
      # is Θ(n²) on the LIST axis and Θ(n²) in comparisons — so uniquing one tag per node
      # would make the finisher quadratic in the node count on EVERY shape, including the ones
      # where both arms are linear. The grouping is already built and its keys are exactly the
      # distinct tags. Same trap `coneRank` records for the same reason.
      tags = builtins.attrNames membersOf;
      # Deduplicated the same way, and the targets come out SORTED rather than in accessor
      # order — so the condensation's edge lists are a function of the graph and not of the
      # order a caller's `edges` happens to enumerate.
      condEdges = prelude.genAttrs tags (
        r:
        builtins.filter (t: t != r) (
          builtins.attrNames (
            prelude.genAttrs (map (m: tagOf.${m}) (prelude.concatMap (m: edges m) (membersOf.${r} or [ ]))) (
              _: true
            )
          )
        )
      );
      # ONE ordering pass over the quotient supplies BOTH published order-shaped fields, and
      # neither routes through a capped fixpoint. `coneRank` warms a memoized longest-path
      # recurrence along the ordering arm's order, so its rank map IS the longest-path DP and
      # its emitted order IS a reverse-topological order: a class that points at another has
      # a strictly greater rank, so it sorts strictly later. The quotient is acyclic, so the
      # cyclic-cone refusal below it is unreachable from here.
      ranked = order.coneRank { edges = r: condEdges.${r} or [ ]; } tags;
    in
    {
      reps = ranked.order;
      bottomUp = ranked.order;
      members = membersOf;
      sccs = map (r: membersOf.${r} or [ ]) ranked.order;
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
  nodeTags =
    accessor@{ edges, nodes, ... }:
    let
      rev = global.transpose accessor;
      forward = prelude.genAttrs nodes (v: traverse.reachableFrom { inherit edges; } v);
      backward = prelude.genAttrs nodes (
        v: prelude.genAttrs (traverse.reachableFrom { inherit (rev) edges; } v) (_: true)
      );
    in
    prelude.genAttrs nodes (
      v: tagOfMembers ([ v ] ++ builtins.filter (u: backward.${v} ? ${u}) forward.${v})
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
  workTags =
    accessor@{ edges, nodes, ... }:
    let
      rev = global.transpose accessor;
      step =
        acc: v:
        if acc.tags ? ${v} then
          acc
        else
          let
            live = id: !(acc.tags ? ${id});
            forward = prelude.genAttrs (traverse.reachableFrom {
              edges = id: builtins.filter live (edges id);
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
            tags = acc.tags // prelude.genAttrs component (_: tag);
          };
    in
    (builtins.foldl' step { tags = { }; } nodes).tags;

  # ── THE ARMS, PUBLISHED BY NAME ──
  # Each is the finisher over one arm's tag map, so the two differ in HOW the partition is
  # found and in nothing else a caller can observe. That is what makes them complementary
  # rather than ranked: neither refuses input the other accepts, and a caller that must have
  # one of them can say so.
  fbNode = accessor: condensationOf accessor (nodeTags accessor);
  fbWork = accessor: condensationOf accessor (workTags accessor);

  # ── THE FRONT DOOR ──
  # The default is the per-node arm, and the delegation is an IDENTITY rather than a wrapper,
  # which is the only spelling that cannot drift from what it delegates to. Changing the
  # default changes this line and nothing a caller of `fbNode` or `fbWork` depends on.
  #
  # The default sits on the arm with no accumulator and no recursion, and neither forward–
  # backward arm reaches a capped fixpoint, so the default path has no iteration cap to
  # inherit and no refusal that names something other than the caller's graph.
  condensation = fbNode;
in
{
  inherit
    condensation
    condensationOf
    fbNode
    fbWork
    ;
}
