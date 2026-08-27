# The partition arms' CEILING cells, and the unforced construction that has one.
#
# WHY THIS IS NOT A TEST. A `stack overflow; max-call-depth exceeded` is an ABORT, not a
# throw: `tryEval` does not catch it, so no in-language assertion can observe one and neither
# runner can host this cell. The only instrument that reads an abort is the EXIT CODE of a
# separate evaluation — the shape `ci/bench/sentinel.sh` establishes and
# `ci/bench/cone-ceiling.sh` follows.
#
# FOUR ARMS, and the third one is the point:
#   fbNode   — the per-node forward–backward arm, the door's default;
#   fbWork   — the worklist forward–backward arm;
#   unforced — the worklist arm written the OTHER way: a `remaining` set read every round and
#              a tag map written every round and read in none. It is CHARACTERIZATION of
#              TODAY's practical limitation, not a control: informational, printed and never
#              gated, useful for watching the boundary recede across evaluator versions (RULED
#              2026-08-27 — infinite scale is the ideal; nothing here may assert this limit
#              persists). A run in which it returns is a run whose component count was too
#              small to reach the chain, and it says nothing about the two arms beside it;
#   closure  — the closure arm, whose ceiling is a fixpoint iteration cap rather than a stack
#              depth, and which therefore THROWS where the others would abort. It is here so
#              the difference between the two failure modes is read on one instrument.
#
# FOUR CONTROLS, so a green row is admissible at all:
#   okControl    — returns 1;
#   catchControl — `tryEval (throw …)`, which says the catcher works in this evaluation;
#   abortControl — a FIXED-DEPTH 50,000 per-atom recursion, so it fires at every cell
#                  including the small ones. A sweep in which it does not fire is INVALID.
#   canary       — THE CONSTRUCTED CANARY: a self-recursion with NO base case, ever — true
#                  divergence, not an environmental limit the way `unforced`'s bisected
#                  boundary is. It carries the liveness obligation `unforced`'s header used to
#                  claim: it reds iff the bench stops forcing or stops observing aborts, and it
#                  can NEVER red on evaluator improvement, because an unconditional recursion
#                  has no faster path to a result — there isn't one. A sweep in which it does
#                  not fire is INVALID, same as abortControl.
#
# The fixtures are `ci/bench/cost-classes.nix`'s, verbatim, so a ceiling read here and an
# allocation figure read there are about the same graphs.
#
# RUN (per cell — the sweep is the shell script):
#   nix-instantiate --eval --strict --json \
#     --arg n 16000 --argstr shape chain --argstr arm fbWork ./ci/bench/partition-ceiling.nix
# `nix eval --file` does NOT auto-call a function-headed file: it reports `cannot convert a
# function to JSON`, and that is not a ceiling reading.
{
  n ? 16000,
  shape ? "chain",
  arm ? "fbWork",
}:
let
  # The prelude shim from `default.nix`, repeated rather than imported, because the control
  # arm below has to be built on the SAME prelude the library uses — a copy of the fold over a
  # different `genAttrs` would be measuring something else.
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

  ix = m: builtins.genList (i: i) m;
  key = p: i: p + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000" + toString i;
  pad =
    i:
    let
      s = toString i;
      z = builtins.substring 0 (5 - builtins.stringLength s) "00000";
    in
    "n" + z + s;
  fromPairs = ns: pairs: {
    nodes = ns;
    edges =
      let
        m = builtins.listToAttrs pairs;
      in
      k: m.${k} or [ ];
  };

  fixtures = {
    # n singleton components in a line: the shape that maximises COMPONENT COUNT, which is the
    # axis the unforced control dies on.
    chain = fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
    # ONE component of n members: the opposite extreme on the same axis, and the shape where
    # the per-node arm pays its price once per member.
    cycle =
      let
        ringNodes = builtins.genList pad n;
        idxOf = builtins.listToAttrs (
          builtins.genList (i: {
            name = pad i;
            value = i;
          }) n
        );
      in
      {
        nodes = ringNodes;
        edges =
          id:
          let
            i = idxOf.${id};
          in
          [ (pad (if i + 1 < n then i + 1 else 0)) ];
      };
    # n/10 independent 10-chains: n components, bounded depth — the shape a host fleet
    # produces, and the one whose component count is large while no single walk is long.
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
  };
  # An unknown shape refuses as loudly as an unknown arm: a fallback fixture would tag a
  # ceiling reading with a shape nobody measured.
  acc = fixtures.${shape} or (throw "unknown shape ${shape}");

  # THE UNFORCED CONSTRUCTION, as the negative control. Same forward–backward decomposition,
  # same restriction to the unassigned set, and the accumulator split across two fields so the
  # tag map is written every round and read in NONE. `builtins.foldl'` forces the record and
  # not its fields, so one update thunk accumulates per component and the whole chain is
  # forced at the end — an evaluator frame per link, and an abort no caller can catch.
  workUnforced =
    accessor@{ edges, nodes, ... }:
    let
      rev = g.transpose accessor;
      step =
        a: v:
        if !(a.remaining ? ${v}) then
          a
        else
          let
            live = id: a.remaining ? ${id};
            forward = prelude.genAttrs (g.reachableFrom { edges = id: builtins.filter live (edges id); } v) (
              _: true
            );
            component = [
              v
            ]
            ++ builtins.filter (u: forward ? ${u}) (
              g.reachableFrom { edges = id: builtins.filter live (rev.edges id); } v
            );
            tag = builtins.head (builtins.sort builtins.lessThan component);
          in
          {
            remaining = builtins.removeAttrs a.remaining component;
            tags = a.tags // prelude.genAttrs component (_: tag);
          };
      final = builtins.foldl' step {
        remaining = prelude.genAttrs nodes (_: true);
        tags = { };
      } nodes;
    in
    final.tags;

  # `deepSeq` over the whole record, so a cell cannot pass by leaving the expensive field a
  # thunk. Every arm reports the same three readings, so a row is comparable across arms.
  report =
    tags:
    builtins.deepSeq tags {
      inherit arm shape n;
      assigned = builtins.length (builtins.attrNames tags);
      components = builtins.length (prelude.unique (builtins.attrValues tags));
    };
  doorReport =
    c:
    builtins.deepSeq c {
      inherit arm shape n;
      assigned = builtins.length (builtins.attrNames c.sccOf);
      components = builtins.length c.sccs;
      inherit (c) depth;
    };
in
if arm == "fbNode" then
  doorReport (g.fbNode acc)
else if arm == "fbWork" then
  doorReport (g.fbWork acc)
else if arm == "closure" then
  doorReport (g.condensationClosure acc)
else if arm == "unforced" then
  report (workUnforced acc)
else if arm == "okControl" then
  1
else if arm == "catchControl" then
  builtins.tryEval (throw "catchControl")
else if arm == "abortControl" then
  # FIXED depth, not the cell's `n`: a control scaled to the cell would stop firing exactly
  # where the cell got small, which is where it is most needed.
  (
    let
      down = i: if i <= 0 then 0 else 1 + down (i - 1);
    in
    down 50000
  )
else if arm == "canary" then
  # UNCONDITIONAL: no depth argument, no base case — unlike `abortControl`, which is a large
  # but FINITE recursion that merely exceeds today's call-depth budget, this one has no budget
  # at which it would return. Measured signature (this evaluator): CALLDEPTH, via the same
  # `stack overflow; max-call-depth exceeded` reading `abortControl` produces.
  (
    let
      down = i: down (i + 1);
    in
    down 0
  )
else
  throw "unknown arm ${arm}"
