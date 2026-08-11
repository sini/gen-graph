# Allocation benchmark for the library's overlapping COST CLASSES — sets of surfaces
# that share one cost because they share one call, and so must be documented from one
# measurement rather than per-function.
#
# ★ THIS PATH IS A FIXED CITATION TARGET. `README.md` and `lib/global.nix` cite it by
# path as the re-run command behind their figures, so renaming this file breaks those
# citations — the same anchor-decay class this file's own branch was written to retire.
# The name is deliberately about the SUBJECT, not about any one arm, so new arms can be
# added without it going stale. Add arms; do not rename.
#
# The two classes measured here:
#
#   1. the two terms `topoOrder`'s CYCLE PATH pays — a `global.cycles` call and a
#      `global.condensation` call (`lib/order.nix`, the `ok = false` branch);
#   2. the `fp.transitiveClosure`-INHERITING class — every surface whose cost is a
#      closure call: `dependents` (`global.nix`), `condensation` (twice: the graph
#      closure and the quotient closure), and `transitiveReduction` (`fixpoint.nix`).
#      These share one cost and must be documented from one measurement, or a reader
#      comparing two rows infers a distinction that does not exist.
#   3. the ORDERING loop — `topoOrder`'s Kahn emission loop, whose cost is the two
#      accumulators it carries plus the ready set. None of the three is visible on a shape
#      that never enters the loop. The emitted sequence is a run list under a binary-counter
#      carry (Θ(n log n)) and the indegree map is a residue over a periodically rebuilt base,
#      so the loop's allocation now tracks what each step CHANGES rather than the width of
#      what it carries; the shapes below are what say whether that holds on a given graph.
#
# ★ THE FIRST TWO CLASSES CANNOT SEE THE THIRD, AND THE REASON IS STRUCTURAL. `complete`
# and `cycle` are cyclic BY CONSTRUCTION — they exist to price the cycle path, which needs
# a cycle — so on both of them every node has indegree ≥ 1, the initial ready set is EMPTY,
# and the emission loop runs ZERO STEPS. A file whose only two shapes are cyclic prices the
# library's failure path and nothing about its success path. Hence the acyclic shapes below:
# the requirement was new SHAPES, not only new arms. `initialReady` is read on every run and
# is the control that says which of the two regimes a cell is in.
#
# WHY THIS EXISTS: the cycle path's cost comment once named a single dominant
# term. It cannot. Which of the two terms is larger flips with the graph shape
# AND with the allocation axis, so any comparative claim about them has to be
# measured on both shapes and all three axes rather than argued.
#
# ★ THE COUNTERS ARE A LOWER BOUND. `list.elements`/`sets.elements`/`nrLookups`
# count Nix-heap allocation only. `genericClosure` keeps its done-set in C++, so its
# key comparisons appear in NONE of the three axes. Every figure here is a floor on
# the real cost, not the bill; state that limit rather than closing it with a number.
#
#   4. the CONE RANK, which is the ordering loop plus a memoized recurrence: `coneRank`
#      warms its memo map along `topoOrderKahn`'s order, so it pays one ordering pass that
#      the pre-remediation construction did not. That constant is what the `coneRank` /
#      `coneRankShipped` pair prices. ★ There is NO BUDGET here and none is invented: the
#      pair exists so the price is filed with its derivation rather than accepted silently,
#      and it is to be re-derived whenever the construction changes.
#      ★ THE BASELINE ARM IS NOT MEASURABLE EVERYWHERE, which is the point of the surface
#      it replaced: `coneRankShipped` ABORTS (`max-call-depth`, uncatchable) on `chain` past
#      ~4,000 and on `deepwide` at every size, so its column simply stops there. Reading a
#      ratio against a cell that aborted is not a comparison; `ci/bench/cone-ceiling.sh` is
#      where that abort is the subject rather than a missing figure.
#
# INTERFACE — `arm` × `shape` × `n`:
#   arm   = cycles | condensation | dependents | transitiveClosure
#         | transitiveReduction | topoOrder | coneRank | coneRankShipped | floor
#         | sentinel | sentinelPeerOrder | sentinelPeerClosure | sentinelVerdict
#   shape = complete | cycle | chain | wide | fleet | discrim | total | deepwide
#   n     = node count (use doublings, e.g. 50/100/200, so a ratio reads as 2^exp)
#
# The four `sentinel*` arms ignore `shape` and `n` — their cells are fixed in the file (see
# the sentinel block). Read them through `./ci/bench/sentinel.sh`, not by hand.
#
# CYCLIC FIXTURES, and why these two:
#   `complete` — the complete digraph: every node points at every other. Out-degree
#     is n-1 (UNBOUNDED) and the whole graph is ONE SCC, so the cycle path really
#     runs. This is the shape a "dense" claim quantifies over.
#   `cycle` — the simple cycle: out-degree 1 (BOUNDED), one SCC, diameter n.
#     The bounded-out-degree counterpart, and the shape that shows the ordering
#     between the two terms is not fixed.
#   Both are CYCLIC by construction: a complete DAG is acyclic and orders
#   successfully, so it never reaches the cycle path at all and cannot be used
#   to price it.
#
# ACYCLIC FIXTURES, for the ordering loop. ★ A shape name does not identify a fixture: the
# KEY ORDER is part of it. Two constructions of the same graph, differing only in whether a
# deep leg's keys sort before or after a wide part's, differ by 3x in ready-set cost. Each
# shape below therefore states its key order, and `initialReady` is read on every run.
#   `chain` — node i depends on i-1. The ready set never holds more than one element, so it
#     is where the ready-set term is a DEAD PREDICATE. Keys ascend with depth.
#   `wide` — n/2 independent 2-chains. n/2 ready at the start and an arrival on n/2
#     consecutive steps. Every producer key (`a`) sorts below every consumer key (`b`).
#   `fleet` — n/10 independent 10-chains: the shape a host fleet produces.
#   `discrim` — n/2 nodes ready at the start, each releasing one whose key sorts BELOW every
#     node still waiting, so greedy min-key must interleave where a tail-append would not.
#     The one shape here on which two DIFFERENT valid topological orders are distinguishable.
#   `total` — the total order: node i depends on every j > i. The ACYCLIC counterpart of
#     `complete`, and the only shape here that is two things at once. It is the DENSE shape,
#     `E = n(n-1)/2`, so a per-edge figure divides by 1,999,000 at n = 2000 — the shape any
#     "dense" claim about ordering quantifies over, and the one the cyclic `complete` cannot
#     supply because it never enters the emission loop. It is also the MAXIMUM-FAN-IN shape:
#     one node is ready at the start and its emission decrements every other node at once, so
#     the indegree residue is Θ(n) wide immediately. Every other acyclic shape here has
#     indegree exactly one, which leaves the residue empty at every step and the loop's
#     residue-fold branch unreached — this is the only committed cell that reaches it.
#     ★ Its FIXTURE is Θ(n²) by construction (`fromPairs` materializes n dependency lists
#     averaging n/2), so `arm=floor` is the term to read a library figure against here, and
#     it is large. Cap it at n = 2000 unless you mean to wait.
#   `deepwide` — one 4000-node chain PLUS (n-4000)/2 independent 2-chains, so depth and
#     width are ADDITIVE rather than multiplicative. It REFUSES below n = 4002 rather than
#     degrading to a shape that was never measured, so it does not run at this file's small
#     default sizes; give it 8000/16000/32000.
#
#   `floor` deep-forces the caller's edge set alone — the fixture's own cost,
#   containing no gen-graph work — so a library figure can be read against it.
#
# The `condensation` arm forces `.sccs`. `lib/order.nix` instead applies `.sccOf`
# to every cyclic key, which forces the same transitive closure, so this arm's
# cost class is the one the cycle path actually pays.
#
# ★ BEFORE QUOTING ANY `sets.elements` FIGURE FROM THIS FILE, read the harness sentinel:
#
#   ./ci/bench/sentinel.sh     ⇒ verdict = "STABLE" | "SHIFTED-BENIGN"
#                                        | "SHIFTED-STRUCTURAL" | "UNUSABLE"
#
# `sets` figures are comparable only within one revision of this file, and the sentinel is
# what says which revision you are on. `STABLE` publishes. `SHIFTED-BENIGN` means re-run
# every cell on the frozen file, re-pin, and publish WITH THE OFFSET LEFT IN. The other two
# do not publish. See the sentinel block below for its operating assumption.
#
# RUN (all three axes; a single-axis read is what this file exists to prevent):
#   NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/s.json nix-instantiate --eval --strict \
#     --arg n 200 --argstr arm condensation --argstr shape cycle ./ci/bench/cost-classes.nix
#   nix-instantiate --eval --raw -E 'let s = builtins.fromJSON (builtins.readFile "/tmp/s.json"); in
#     "${toString s.list.elements} ${toString s.sets.elements} ${toString s.nrLookups}"'
{
  n ? 50,
  arm ? "cycles",
  shape ? "complete",
  observed ? null,
}:
let
  # `default.nix`'s prelude shim, spelled out here so the library and the baseline arm below
  # share ONE prelude: a copy of the rank recurrence built on a second evaluation of
  # gen-prelude would price that second evaluation as if it were the construction.
  prelude =
    let
      lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
      node = lock.nodes.gen-prelude.locked;
    in
    import "${
      builtins.fetchTree {
        inherit (node)
          type
          owner
          repo
          rev
          narHash
          ;
      }
    }/lib";
  g = import ../../lib { inherit prelude; };

  # THE PRE-REMEDIATION `coneRank`, verbatim at `f3b520f`: the memoized recurrence and the
  # `(depth, id)` sort, with nothing forcing the map in any particular order. It is the
  # BASELINE the remediated arm is priced against, and it is reproduced rather than cited
  # because a price quoted from a figure nobody can re-run is not a price.
  coneRankShipped =
    accessor: cone:
    let
      coneSet = prelude.genAttrs cone (_: true);
      inConeProducers = id: builtins.filter (d: coneSet ? ${d}) (accessor.edges id);
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
      order = builtins.sort (
        a: b: if depth.${a} == depth.${b} then a < b else depth.${a} < depth.${b}
      ) cone;
    in
    {
      inherit order depth;
    };

  # zero-padded so ids sort lexicographically in index order
  pad =
    i:
    let
      s = toString i;
      z = builtins.substring 0 (5 - builtins.stringLength s) "00000";
    in
    "n${z}${s}";
  ix = m: builtins.genList (i: i) m;
  # Every acyclic fixture precomputes a dependency attrset and exposes the SAME accessor
  # shape, `k: m.${k} or [ ]`, so the accessor is a Θ(n) preamble cost in each and no shape
  # gets a cheaper one than another.
  fromPairs = ns: pairs: {
    nodes = ns;
    edges =
      let
        m = builtins.listToAttrs pairs;
      in
      k: m.${k} or [ ];
  };
  key = p: i: p + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000" + toString i;

  # The deep leg's length, past the rank recurrence's ceiling.
  deepwideD = 4000;

  # Parameterised by SIZE rather than closing over the caller's `n`, so the sentinel below
  # can instantiate its own fixed cells from the same builders every other arm uses.
  mkFixtures =
    n:
    let
      # Shared per instantiation, NOT rebuilt per edge call: `cycleEdges` is O(1) amortised
      # because `idxOf` is one binding the whole fixture reads. Rebuilding it inside `edges`
      # would make the accessor O(n) per call and silently move every closure-class figure
      # this file already publishes.
      ringNodes = builtins.genList pad n;
      idxOf = builtins.listToAttrs (
        builtins.genList (i: {
          name = pad i;
          value = i;
        }) n
      );
    in
    {
      complete = {
        nodes = ringNodes;
        edges = id: builtins.filter (x: x != id) ringNodes;
      };
      cycle = {
        nodes = ringNodes;
        edges =
          id:
          let
            i = idxOf.${id};
          in
          [ (pad (if i + 1 < n then i + 1 else 0)) ];
      };
      chain = fromPairs (map (key "n") (ix n)) (
        map (i: {
          name = key "n" i;
          value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
        }) (ix n)
      );
      wide =
        let
          m = n / 2;
        in
        fromPairs (map (key "a") (ix m) ++ map (key "b") (ix m)) (
          map (i: {
            name = key "b" i;
            value = [ (key "a" i) ];
          }) (ix m)
        );
      fleet =
        let
          c = n / 10;
          k =
            i: d:
            "h"
            + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000"
            + toString i
            + "-"
            + toString d;
        in
        fromPairs (builtins.concatLists (map (i: map (k i) (ix 10)) (ix c))) (
          builtins.concatLists (
            map (
              i:
              map (d: {
                name = k i d;
                value = if d == 0 then [ ] else [ (k i (d - 1)) ];
              }) (ix 10)
            ) (ix c)
          )
        );
      discrim =
        let
          m = n / 2;
        in
        fromPairs (map (key "m") (ix m) ++ map (key "a") (ix m)) (
          map (i: {
            name = key "a" i;
            value = [ (key "m" i) ];
          }) (ix m)
        );
      total = fromPairs (map (key "n") (ix n)) (
        map (i: {
          name = key "n" i;
          value = map (j: key "n" (i + 1 + j)) (ix (n - i - 1));
        }) (ix n)
      );
      deepwide =
        let
          m = (n - deepwideD) / 2;
        in
        if n < deepwideD + 2 then
          throw "shape deepwide requires n >= ${toString (deepwideD + 2)} (one ${toString deepwideD}-chain plus at least one pair); got ${toString n}"
        else
          fromPairs (map (key "c") (ix deepwideD) ++ map (key "a") (ix m) ++ map (key "b") (ix m)) (
            map (i: {
              name = key "c" i;
              value = if i == 0 then [ ] else [ (key "c" (i - 1)) ];
            }) (ix deepwideD)
            ++ map (i: {
              name = key "b" i;
              value = [ (key "a" i) ];
            }) (ix m)
          );
    };

  # An unknown SHAPE must refuse exactly as loudly as an unknown ARM. Falling through
  # to a default fixture would tag a real figure with a shape that was never measured.
  fixtures = mkFixtures n;
  acc = fixtures.${shape} or (throw "unknown shape ${shape}");
  inherit (acc) nodes edges;

  # ── THE HARNESS SENTINEL ──────────────────────────────────────────────────────────
  # A shared bench file is a MUTABLE INSTRUMENT. Adding one attribute to the dispatch
  # attrset shifts `sets.elements` on every arm reached through it — measured on THIS file, by
  # replaying four revisions of it against one fixed library: adding the SENTINEL shifted
  # `sets` +1 on every pre-existing cell with `list.elements` bit-identical on all of them,
  # and the revision that added the shape controls shifted `sets` again while ALSO adding
  # `list` (+n on `cycle`, +n(n-1) on `complete` — the controls force `edges k` per node, and
  # on a complete digraph that is the whole edge set). So a `sets` figure quoted across an
  # edit is wrong by a constant nobody sees, and a `list` figure can be too. The sentinel exists to make that constant visible instead of silent.
  #
  # It is ON THE EVALUATION PATH BOTH WAYS, because either alone is insufficient: it is
  # dispatched through the same `table` as every other arm AND it calls gen-graph. A guard
  # sees a harness change iff the change is on the guard's own evaluation path, and calling
  # the library is one sufficient way onto that path rather than the only one.
  #
  # ★ It reports a CLASSIFICATION, not pass/fail. The shift a bench edit produces is benign
  # — one axis, uniform, no exponent or ratio moves — and an arm that cries red on a benign
  # shift gets disabled, which leaves the class unguarded while looking guarded.
  #
  # ★★ ITS OPERATING ASSUMPTION IS ONE CHANGE AT A TIME, and a future reader needs this to
  # interpret a SHIFTED-STRUCTURAL reading. Uniformity is what separates a harness edit from
  # a subject move, but TWO benign changes on DIFFERENT evaluation paths sum to a
  # non-uniform delta and read as structural. Measured instance: a bench edit (+3 on every
  # cell, via the dispatch attrset) landing together with a gen-prelude bump (+6 on the
  # cells whose evaluation path reaches the prelude, and 0 on the rest) produced a delta of
  # +9 on some cells and +3 on others — single-axis and non-uniform, i.e. SHIFTED-STRUCTURAL
  # by the rule, while `list.elements` and `nrLookups` were bit-identical on every cell and
  # nothing about the subject had moved. On a SHIFTED-STRUCTURAL reading, first ask whether
  # more than one thing changed; the verdict is a prompt to decompose, not a conviction.
  #
  # ★★ THE SAME VERDICT IS ALSO WHAT A GENUINE SUBJECT MOVE PRODUCES, and the third cell is
  # what tells the two apart: `peerClosure` reaches no ordering code, so a change to the
  # ordering loop leaves it bit-identical while both `topoOrder` cells move. A harness edit is
  # the opposite shape — it moves every cell, including the one that calls no changed code.
  # Read the decomposition before the verdict, and re-pin from the frozen file in the same
  # commit as the change that moved it.
  #
  # ★★★ AND THE WAY TO DECOMPOSE A DELTA THAT IS BOTH AT ONCE IS TO MEASURE THEM APART: check
  # the harness edit out against the OLD library in a detached worktree, read the cells there,
  # and the residue is the library's. Done for the pins below, which carry both:
  #   · adding one shape to `mkFixtures` — `list` and `nrLookups` bit-identical on every cell,
  #     `sets` +1 UNIFORMLY on all three, i.e. SHIFTED-BENIGN, the dispatch-attrset offset
  #     this guard was built to make visible;
  #   · the ordering loop's own change — `nrLookups` +64 on both `topoOrder` cells and 0 on
  #     `peerClosure`, `list` and `sets` untouched.
  # Summed they are single-cell-non-uniform and read SHIFTED-STRUCTURAL, which is correct and
  # says nothing about either part. Neither is legible in the sum; both are obvious apart.
  #
  # The pins are the readings of THIS file at the revision that last re-derived them. They
  # are `sets.elements`-bearing and therefore comparable only within one bench revision:
  # when the sentinel reports SHIFTED-BENIGN, re-run every cell on the frozen bench, re-pin
  # from that run, and publish WITH THE OFFSET LEFT IN. Never subtract it — subtracting
  # makes the published figure irreproducible from the stated command.
  #
  # Three cells, because uniformity cannot be established from one: the sentinel proper and
  # TWO further library arms, so it is never read alone. Their shapes and sizes are FIXED
  # here and do not read `n`/`shape` — a pin against a caller-chosen size is not a pin.
  # ★ RE-PINNED, and the offset is LEFT IN. The previous pins read `sets` 2791 / 4181 / 8068;
  # the remediation that published `topoOrderKahn`, `forgetLabels` and `cyclicEdgesWhere` and
  # moved `coneRank` into `lib/order.nix` shifted `sets` by +10 on ALL THREE cells with
  # `list` and `nrLookups` bit-identical on every one — SHIFTED-BENIGN by the rule above, and
  # the export set is on every cell's evaluation path, which is why even `peerClosure`
  # (reaching no ordering code) moved. Decomposed as the block above prescribes: the bench
  # edit that added the `coneRank` arms contributed ZERO — the three cells read the same on
  # the edited file as on the unedited one — so the whole +10 is the library's.
  sentinelPins = {
    sentinel = {
      list = 2740;
      sets = 2801;
      nrLookups = 4332;
    };
    peerOrder = {
      list = 2461;
      sets = 4191;
      nrLookups = 7705;
    };
    peerClosure = {
      list = 490790;
      sets = 8078;
      nrLookups = 29000;
    };
  };
  sentinelCells = {
    sentinel = {
      arm = "topoOrder";
      shape = "chain";
      n = 64;
    };
    peerOrder = {
      arm = "topoOrder";
      shape = "wide";
      n = 64;
    };
    peerClosure = {
      arm = "condensation";
      shape = "cycle";
      n = 32;
    };
  };
  sentinelArmOf = {
    sentinel = "sentinel";
    sentinelPeerOrder = "peerOrder";
    sentinelPeerClosure = "peerClosure";
  };
  sentinelCell = sentinelArmOf ? ${arm};
  sentinelCellName = sentinelArmOf.${arm} or "";
  sentinelAxes = [
    "list"
    "sets"
    "nrLookups"
  ];
  sentinelNames = builtins.attrNames sentinelPins;

  # ★ UNUSABLE NEVER COLLAPSES TO STABLE. A reading that is absent, non-integer or
  # incomplete is a sentinel that did not run, and "did not run" must never be reported as
  # "did not move" — that is the failure mode where a comparator compares two empty
  # readings and prints the reassuring answer.
  sentinelUsable =
    observed != null
    && builtins.isAttrs observed
    && builtins.all (
      nm:
      observed ? ${nm}
      && builtins.all (a: observed.${nm} ? ${a} && builtins.isInt observed.${nm}.${a}) sentinelAxes
    ) sentinelNames;
  sentinelDelta = nm: a: observed.${nm}.${a} - sentinelPins.${nm}.${a};
  sentinelMoved = builtins.filter (
    a: builtins.any (nm: sentinelDelta nm a != 0) sentinelNames
  ) sentinelAxes;
  sentinelUniform =
    a:
    let
      ds = map (nm: sentinelDelta nm a) sentinelNames;
    in
    builtins.all (d: d == builtins.head ds) ds;
  sentinelVerdict =
    if !sentinelUsable then
      "UNUSABLE"
    else if sentinelMoved == [ ] then
      "STABLE"
    else if builtins.length sentinelMoved == 1 && sentinelUniform (builtins.head sentinelMoved) then
      "SHIFTED-BENIGN"
    else
      "SHIFTED-STRUCTURAL";

  result =
    if arm == "cycles" then
      g.cycles acc
    else if arm == "condensation" then
      (g.condensation acc).sccs
    # `dependents` is curried (accessor -> targetId) and computes the FULL closure
    # before filtering, so the closure cost is paid whichever target is named.
    else if arm == "dependents" then
      g.dependents acc (builtins.head nodes)
    else if arm == "transitiveClosure" then
      g.transitiveClosure acc
    else if arm == "transitiveReduction" then
      g.transitiveReduction acc
    # The ORDERING loop. On an acyclic shape this returns `.order` and the emission loop
    # runs n steps; on `complete`/`cycle` it returns the cycle REPORT instead and prices the
    # failure path, which is arms 1 and 2 over again. `initialReady` below says which.
    else if arm == "topoOrder" then
      let
        r = g.topoOrder acc;
      in
      if r.ok then r.order else r.cycles
    # The CONE RANK, both arms. `.order` is forced FIRST and cold, which is the read both
    # real consumers make and also the only one that reaches the pre-remediation ceiling:
    # deep-forcing the whole result instead would force `depth` first (sorted attribute
    # order), and on `chain` that forcing order is topological, so the baseline arm would
    # return at 32,000 and the pair would price two constructions that never diverged.
    else if arm == "coneRank" then
      let
        r = g.coneRank acc nodes;
      in
      builtins.deepSeq r.order r.depth
    else if arm == "coneRankShipped" then
      let
        r = coneRankShipped acc nodes;
      in
      builtins.deepSeq r.order r.depth
    else if arm == "floor" then
      builtins.deepSeq (map edges nodes) nodes
    # The sentinel's own measurable body: `topoOrder` over a FIXED tiny graph, so the cell
    # is dispatched through this same table AND calls gen-graph. It ignores `n`/`shape` by
    # design — see sentinelCells.
    else if arm == "sentinel" then
      (g.topoOrder (mkFixtures 64).chain).order
    else if arm == "sentinelPeerOrder" then
      (g.topoOrder (mkFixtures 64).wide).order
    else if arm == "sentinelPeerClosure" then
      (g.condensation (mkFixtures 32).cycle).sccs
    else
      throw "unknown arm ${arm}";
in
if arm == "sentinelVerdict" then
  {
    verdict = sentinelVerdict;
    pins = sentinelPins;
    cells = sentinelCells;
    inherit observed;
    movedAxes = if sentinelUsable then sentinelMoved else [ ];
    deltas =
      if sentinelUsable then
        builtins.listToAttrs (
          map (nm: {
            name = nm;
            value = builtins.listToAttrs (
              map (a: {
                name = a;
                value = sentinelDelta nm a;
              }) sentinelAxes
            );
          }) sentinelNames
        )
      else
        { };
  }
# ★★ A SENTINEL CELL MUST NOT FORCE THE CALLER'S FIXTURE. The pins are readings of the whole
# EVALUATION, not of the arm's body alone, so anything else the run forces is inside them —
# and the shape controls below force `nodes` and every `edges k`. With them, the same
# `arm=sentinel` reads `list.elements` 3,549 at `n=1 shape=chain` and **64,003,545** at
# `n=8000 shape=complete`: a pin off by four orders of magnitude, decided by two arguments the
# sentinel does not otherwise use. That is not a caveat to document, it is a dependency to
# remove — a guard whose reading depends on how it happens to be invoked reports on the
# invocation, and the next reader re-pins from whichever one they ran. The sentinel arms
# therefore skip the shape controls entirely, and their reading is now invariant under
# `n`/`shape` (verified across `n=1 chain`, `n=200 chain`, `n=200 complete`, `n=8000
# complete`). Do not add a control here that touches `nodes` or `edges`.
else if sentinelCell then
  builtins.deepSeq result {
    inherit arm;
    cell = sentinelCells.${sentinelCellName};
    len =
      if builtins.isList result then
        builtins.length result
      else
        builtins.length (builtins.attrNames result);
  }
else
  builtins.deepSeq result {
    inherit arm shape n;
    # SHAPE CONTROL for the ordering class, read on every run: how many nodes have no
    # dependencies, i.e. how many steps the Kahn loop starts with. ZERO means the emission
    # loop never runs and the cell says nothing about the ordering cost — which is exactly
    # what `complete` and `cycle` report, and why they could not price this class.
    initialReady = builtins.length (builtins.filter (k: edges k == [ ]) nodes);
    nodeCount = builtins.length nodes;
    # SHAPE CONTROL, read on every run: both fixtures must be ONE SCC, or the arm is
    # not measuring the cycle path's regime. `cycles` ⇒ len n, `condensation` ⇒ len 1.
    # `transitiveClosure` ⇒ len n. `dependents` ⇒ len n-1 (target filtered out).
    # `transitiveReduction` ⇒ len 0 on `complete`: every edge is implied by a two-hop
    # path, and `differenceEdges` drops a key whose row empties — producing that answer
    # still forces the closure, which is the cost being measured.
    len =
      if builtins.isList result then
        builtins.length result
      else
        builtins.length (builtins.attrNames result);
  }
