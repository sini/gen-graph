# WHY `coneRank`'s cyclic refusal works: the driver's VERDICT is consulted BEFORE the memo
# map is entered. This file is the discriminator for that clause, and it is a discriminator
# rather than a control because of what it holds fixed.
#
# ONE CONSTRUCTION, ONE SWITCH. Every arm below computes the same driver over the same cone
# and builds the same memoized recurrence. The only thing `readMemoFirst` changes is which
# of the two `seq`s runs first. An arm that simply OMITTED the driver would separate
# "driver absent" from "driver present", which nobody disputes and which says nothing about
# the clause: the clause is that a driver present AND COMPUTED is not enough.
#
# WHY IT IS NOT A TEST. The wrong order produces `infinite recursion encountered` — the
# evaluator's black-hole detector firing on a thunk that depends on itself — and that abort
# ESCAPES `tryEval` and kills the runner rather than failing a cell. The only instrument
# that reads it is the exit code of a separate evaluation.
#
# The mechanism, so the reading is interpretable: memoization is what makes a cyclic cone
# self-referential, so the detector fires at the FIRST thunk re-entry, after traversing the
# cycle exactly once — at depth 2 on a 2-cycle, nowhere near any bound. That is why no size
# limit could have caught it and why keeping the memo (which every construction in this
# cost class does) means the refusal has to come from consulting the driver first.
#
# RUN (per arm; the sweep is `cone-consultation.sh`):
#   nix-instantiate --eval --strict --json --argstr arm lateCyclic ./ci/bench/cone-consultation.nix
{
  arm ? "earlyCyclic",
}:
let
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

  mkAcc = m: {
    nodes = builtins.attrNames m;
    edges = id: m.${id} or [ ];
  };
  # a -> b -> c -> a
  cyclic = mkAcc {
    a = [ "b" ];
    b = [ "c" ];
    c = [ "a" ];
  };
  # `den-hoag-ges2` F1: a 2-cycle at the head of a chain — the abort arrives at depth 2
  # while the cone is four nodes deep.
  cycshort = mkAcc {
    a = [ "b" ];
    b = [ "a" ];
    c = [ "b" ];
    d = [ "c" ];
  };
  acyclic = mkAcc {
    p = [ ];
    q = [ "p" ];
  };

  rank =
    readMemoFirst: accessor: cone:
    let
      coneSet = prelude.genAttrs cone (_: true);
      inConeProducers = id: builtins.filter (d: coneSet ? ${d}) (accessor.edges id);

      # Computed in EVERY arm. What varies is when its verdict is read, never whether it exists.
      driver = g.topoOrderKahn {
        nodes = prelude.unique cone;
        edges = inConeProducers;
      };

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
      # On a cyclic cone the driver emits nothing to warm along, which is the whole point:
      # warming answers the CEILING, and it is the verdict that answers the cycle.
      warmed = builtins.foldl' (acc: id: builtins.seq depth.${id} acc) true (driver.order or [ ]);

      # ENTERING THE MEMO MAP: the comparator forces `depth` cells.
      sorted = builtins.sort (
        a: b: if depth.${a} == depth.${b} then a < b else depth.${a} < depth.${b}
      ) cone;
      enterMemo = builtins.deepSeq sorted true;

      # CONSULTING THE VERDICT.
      consultVerdict =
        if driver.ok then
          true
        else
          throw "gen-graph.coneRank: cyclic cone has no producers-first rank; cycles ${builtins.toJSON driver.cycles}";

      value = builtins.seq warmed {
        order = sorted;
        inherit depth;
      };
    in
    if readMemoFirst then
      builtins.seq enterMemo (builtins.seq consultVerdict value)
    else
      builtins.seq consultVerdict (builtins.seq enterMemo value);

  arms = {
    earlyCyclic = rank false cyclic cyclic.nodes;
    lateCyclic = rank true cyclic cyclic.nodes;
    earlyCycshort = rank false cycshort cycshort.nodes;
    lateCycshort = rank true cycshort cycshort.nodes;
    # POSITIVE CONTROL for the late arms: the late construction is not merely broken. On an
    # acyclic cone it returns the same order the early one does — so what the cyclic late
    # arm demonstrates is the ORDER of consultation, not a construction that never worked.
    earlyAcyclic = rank false acyclic acyclic.nodes;
    lateAcyclic = rank true acyclic acyclic.nodes;
  };
  value = arms.${arm} or (throw "unknown arm ${arm}");
  attempt = builtins.tryEval (builtins.deepSeq value true);
in
{
  inherit arm;
  # `true` = a named, catchable refusal. An UNCATCHABLE abort never reaches this line at all
  # — the evaluation dies and the exit code is the reading.
  caught = !attempt.success;
  # LIVE CONTROL, same run: the catcher works, so a `caught = false` above means the arm
  # returned and not that `tryEval` was asleep.
  control = (builtins.tryEval (throw "live control")).success;
  order = if attempt.success then value.order else null;
}
