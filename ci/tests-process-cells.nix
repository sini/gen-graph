# THE PER-PROCESS CELLS — one counted evaluation per process, read by the runner in
# `tests-process.nix` from the evaluator's own statistics.
#
# WHY THESE CANNOT BE SUITE CELLS. The verdicts are COSTS (thunks and bytes allocated), and a cost
# is a property of one whole evaluator process: a suite cell shares its process with every other
# cell, so its counters are not its own.
#
# THE FIXTURE is gen-merge's bipartite caller-built relation (gen-merge `lib/modules.nix`
# `entryNodes` / `depMap`): e entries, entry i touching locations l_i and l_(i+1); a location's
# edges are the entries touching it, an entry's are none. Every entry is a seed, which is
# gen-merge's warm verdict and gen-memo's multi-seed sites: `unique (seeds ++ concatMap (door acc)
# seeds)`, ONE partial application of the door held across every target. The relation is forced
# for every node first, so what grows with e beyond it is the cone. The answer is the cone's
# size, hand-derived: every entry and every location, 2e + 1.
#
# Arms `<door>-<e>`, e ∈ { 8, 16, 32 }:
#   cone      dependentsOf
#   impact    impactOf (the same helper under its own name)
#   frontier  dependentsFrontier, `prune = _: true`
#   direct    directDependentsOf
#   perapp    dependentsOf RE-APPLIED to the accessor per seed: the live control, whose index is
#             built once per target by construction, so its counters must read the quadratic class.
{
  arm,
  genPreludeSrc,
  libSrc,
}:
let
  prelude = import "${genPreludeSrc}/lib";
  graph = import "${libSrc}" { inherit prelude; };
  inherit (builtins) genList listToAttrs;
  parsed = builtins.match "([a-z]+)-([0-9]+)" arm;
  door = builtins.elemAt parsed 0;
  e = builtins.fromJSON (builtins.elemAt parsed 1);
  ent = i: "entry:${toString i}";
  loc = i: "l${toString i}";
  depMap = listToAttrs (
    genList (j: {
      name = loc j;
      value = (if j > 0 then [ (ent (j - 1)) ] else [ ]) ++ (if j < e then [ (ent j) ] else [ ]);
    }) (e + 1)
  );
  acc = {
    nodes = genList ent e ++ genList loc (e + 1);
    edges = nid: depMap.${nid} or [ ];
  };
  seeds = genList ent e;
  relation = builtins.deepSeq (map acc.edges acc.nodes) null;
  cone = xs: prelude.unique (seeds ++ prelude.concatMap xs seeds);
  arms = {
    cone = cone (graph.dependentsOf acc);
    impact = cone (graph.impactOf acc);
    frontier =
      let
        f = graph.dependentsFrontier acc;
      in
      cone (s: f s (_: true));
    direct = cone (graph.directDependentsOf acc);
    perapp = cone (s: graph.dependentsOf acc s);
  };
in
if parsed == null || !(arms ? ${door}) then
  throw "tests-process-cells: no arm '${arm}'"
else
  builtins.seq relation (builtins.length (builtins.deepSeq arms.${door} arms.${door}))
