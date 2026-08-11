# PLAIN-DATA conformance of the partition door's result, as an exit-code cell.
#
# THE PROPERTY, not a proxy for it: `builtins.toJSON` of the WHOLE result returns. The door is
# a published cross-library surface, so its result is read across a foreign evaluation, where
# only strings, lists, integers and attrsets of those survive — a function's identity is minted
# by the build that made it and does not cross. Serializing the whole record is the direct
# question, and `toJSON` is the instrument that answers it.
#
# WHY THIS IS NOT A TEST. `toJSON` over a function is an UNCATCHABLE ABORT: `tryEval` does not
# contain it (`fnControl` below measures exactly that, in the same run). A cell asserting it
# inside either runner would crash the runner rather than fail a cell, which is why this lives
# on its own output like every other abort-shaped reading in this directory.
#
# TWO ARMED CONTROLS, because a check that cannot fail is not a check:
#   legacy    — the record shape the door published BEFORE the lookups became maps, reproduced
#               here: the same partition with `sccOf`, `members` and `condEdges` as FUNCTIONS.
#               It must FAIL the same cell the door passes, or the cell is not reading what it
#               claims to read;
#   fnControl — `tryEval (toJSON (x: x))`, which must ESCAPE `tryEval` and take the process
#               with it. That is what says the failure mode is an abort and therefore what
#               decides this instrument's shape;
#   okControl — `tryEval (toJSON { x = [ 1 2 ]; })`, the live positive control for the catcher
#               itself: without it, `fnControl`'s rc=1 could be a broken `tryEval` rather than
#               an escaping abort.
#
# RUN (per cell — the sweep is the shell script):
#   nix-instantiate --eval --strict --json \
#     --arg n 60 --argstr shape chain --argstr arm door ./ci/bench/partition-plaindata.nix
{
  n ? 60,
  shape ? "chain",
  arm ? "door",
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
    chain = fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
    # A multi-member component, so the serialized record is not all singletons — a record whose
    # every class has one member cannot show that member lists survive the crossing.
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
  acc = fixtures.${shape} or (throw "unknown shape ${shape}");

  # THE PRE-CHANGE RECORD, reproduced: the same partition, published the way it was published
  # when the lookups were functions. Nothing about the partition differs — only the shape of
  # the three lookup fields — so a difference in the reading is a difference in crossability
  # and nothing else.
  legacyRecord =
    a:
    let
      c = g.condensation a;
    in
    {
      inherit (c) reps bottomUp sccs;
      members = tag: c.members.${tag} or [ ];
      sccOf = id: c.sccOf.${id} or id;
      condEdges = tag: c.condEdges.${tag} or [ ];
    };

  # The whole record serialized, and the length reported: a cell that returned a constant
  # would pass without the serialization ever happening.
  crossed =
    r:
    let
      j = builtins.toJSON r;
    in
    {
      inherit arm shape n;
      jsonLength = builtins.stringLength j;
      crosses = true;
    };
in
if arm == "door" then
  crossed (g.condensation acc)
else if arm == "fbNode" then
  crossed (g.fbNode acc)
else if arm == "fbWork" then
  crossed (g.fbWork acc)
else if arm == "closure" then
  crossed (g.condensationClosure acc)
else if arm == "legacy" then
  crossed (legacyRecord acc)
else if arm == "fnControl" then
  builtins.tryEval (builtins.toJSON (x: x))
else if arm == "okControl" then
  builtins.tryEval (
    builtins.toJSON {
      x = [
        1
        2
      ];
    }
  )
else
  throw "unknown arm ${arm}"
