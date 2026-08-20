# The `coneRank` CEILING cell, and the pre-remediation arm that used to hit it.
#
# WHY THIS IS NOT A TEST. A `stack overflow; max-call-depth exceeded` is an ABORT, not a
# throw: `tryEval` does not catch it (measured, with a live catchable control in the same
# run), so no in-language assertion can observe one. Neither runner can host this cell. The
# only instrument that reads an abort is the EXIT CODE of a separate evaluation, which is
# the shape `ci/bench/sentinel.sh` establishes and `ci/bench/cone-ceiling.sh` follows.
#
# TWO ARMS, and the second one is the point:
#   remediated — the library's `coneRank`, which warms its memo map along the ordering
#                arm's order;
#   shipped    — the PRE-REMEDIATION construction, reproduced verbatim from `f3b520f`: the
#                same memoized recurrence and the same `(depth, id)` sort with nothing
#                forcing the map in any particular order.
# The shipped arm is a LIVE NEGATIVE CONTROL, not a historical curiosity. A run in which it
# returns is a run whose sizes were too small to reach the ceiling, and it says nothing
# about the remediated arm beside it. The script reads both at every cell.
#
# The fixtures are `ci/bench/cost-classes.nix`'s `chain` and `deepwide`, verbatim, so a
# ceiling read here and an allocation figure read there are about the same graphs.
#
# RUN (per cell — the sweep is the shell script):
#   nix-instantiate --eval --strict --json \
#     --arg n 4000 --argstr shape chain --argstr arm remediated ./ci/bench/cone-ceiling.nix
# `nix eval --file` does NOT auto-call a function-headed file, so it is the wrong runner
# here: it reports `cannot convert a function to JSON` and that is not a ceiling reading.
{
  n ? 4000,
  shape ? "chain",
  arm ? "remediated",
}:
let
  # The prelude shim from `default.nix`, repeated rather than imported, because the shipped
  # arm below has to be built on the SAME prelude the library uses — a copy of the
  # recurrence over a different `fix`/`genAttrs` would be measuring something else.
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
  fromPairs = ns: pairs: {
    nodes = ns;
    edges =
      let
        m = builtins.listToAttrs pairs;
      in
      k: m.${k} or [ ];
  };
  deepwideD = 4000;

  fixtures = {
    chain = fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
    deepwide =
      let
        m = (n - deepwideD) / 2;
      in
      if n < deepwideD + 2 then
        throw "shape deepwide requires n >= ${toString (deepwideD + 2)}; got ${toString n}"
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
  # An unknown shape refuses as loudly as an unknown arm: a fallback fixture would tag a
  # ceiling reading with a shape nobody measured.
  acc = fixtures.${shape} or (throw "unknown shape ${shape}");

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

  rank =
    if arm == "remediated" then
      g.coneRank acc acc.nodes
    else if arm == "shipped" then
      coneRankShipped acc acc.nodes
    else
      throw "unknown arm ${arm}";
  # ★ `.order` IS FORCED FIRST, AND COLD. This is load-bearing, not stylistic, and getting
  # it wrong disarms the control silently. `deepSeq` over the whole result forces attributes
  # in sorted-name order — `depth` before `order` — and forcing the whole `depth` map first
  # is precisely the BENIGN case: `genAttrs` forces in sorted key order, which on `chain` is
  # topological, so no descent happens and the SHIPPED arm returns at 32,000. Measured: the
  # first version of this cell did exactly that and reported no ceiling for either arm.
  # `.order` cold is also the read both real consumers make (`gen-memo/lib/eager.nix`,
  # `den-hoag/lib/coordinates.nix`), so it is the cell's subject as well as its discriminant.
  cold = builtins.deepSeq rank.order rank;
in
builtins.deepSeq cold {
  inherit arm shape n;
  emitted = builtins.length cold.order;
  # The deepest rank, read from the map rather than from the shape, so the cell reports a
  # value the construction computed instead of one the fixture already knew.
  deepest = builtins.foldl' (m: k: if cold.depth.${k} > m then cold.depth.${k} else m) 0 acc.nodes;
}
