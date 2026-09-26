# The door's order contract, fenced (den-hoag-nz21). `lib/order.nix` declares three clauses at
# `topoOrder`: TOPOLOGICALITY and PERMUTATION-INDEPENDENCE are promised; WHICH linear extension
# the door emits is declared and pinned, NOT normative. A cell that pins the door's pick is a
# change detector and carries `change-detector` in its name; every other cell must hold under
# any valid order the first two clauses admit.
#
# The fence re-evaluates every OTHER suite file naming the door (`topoOrder` or `phaseOrder`)
# against a genGraph whose DOOR alone emits a different valid, permutation-independent order —
# the arm `topoOrderKahn` is left untouched (it is outside clause 3) — under two perturbations:
#   P0  depth ascending, key DESCENDING under `lessThan`
#   P4  height descending (longest path to a sink), key DESCENDING
# and asserts both directions of the marker:
#   unmarkedRed   — a cell reds under either perturbation and is not a change detector: a
#                   contract cell asserting the door's pick. Must be [ ].
#   deadDetectors — a change detector green under both: a marker on a cell that cannot see
#                   the move it exists for. Must be [ ].
# plus the three clause heads in `lib/order.nix` and `README.md`, and live controls that the
# reach is non-empty and that the perturbations move something.
#
# REACH OF THE GUARANTEE. P0 catches every cell asserting a WHOLE door order on a graph with
# more than one topological order: let k be the first depth level holding two nodes; every
# level below is a singleton chained to the one before, so after that forced prefix Kahn's
# ready set is exactly level k, where min-key takes the smallest key and P0 the largest. That
# holds for any strict total `lessThan`, and for ADR-0009's (depth, key) flip too. It does NOT
# cover a cell asserting a PROJECTION of the order ("c is last", "b before c" on {a,b,c} with
# c→a both slip past P0); P4 is added because it catches those two. No finite family of
# perturbations catches every projection: that needs a realizer of each poset, whose least
# size is its order dimension, unbounded (Dushnik and Miller 1941). The ceiling is inherent.
#
# COST: the fence imports each reach file once per perturbation, so it is the suite's most
# expensive cell. Measured on the host nix-unit, one run each: `./ci#tests` takes 7.4 s
# without it and 13.2 s with it, +79%, about half of that for each perturbation.
args@{ genGraph, ... }:
let
  self = "order-contract-fence.nix";
  inherit (builtins)
    attrNames
    concatMap
    elem
    filter
    foldl'
    genList
    elemAt
    length
    readDir
    readFile
    seq
    sort
    tryEval
    ;
  # `split`, not an anchored `.*x.*` match: that form walks the whole file per call and a 47 KB
  # suite file is exactly where anchored regexes overflow
  hasInfix = infix: s: length (builtins.split infix s) > 1;
  # keys may carry string context (context-node-names.nix); an attribute NAME may not, and the
  # library strips it the same way (`attrKey`)
  ak = builtins.unsafeDiscardStringContext;
  reverseList =
    l:
    let
      n = length l;
    in
    genList (i: elemAt l (n - 1 - i)) n;

  # longest path from a source (`depth`) and to a sink (`height`), read off a valid
  # producers-first `order` and the same edges; each value is forced as it is stored, so a
  # 12,000-node chain folds without a thunk chain
  depthOf =
    keyOf: depsOf: order:
    foldl' (
      acc: n:
      let
        v = foldl' (m: d: if acc.${ak d} + 1 > m then acc.${ak d} + 1 else m) 0 (depsOf n);
      in
      seq v (acc // { ${ak (keyOf n)} = v; })
    ) { } order;
  heightOf =
    keyOf: depsOf: order:
    let
      users = foldl' (
        acc: n: foldl' (a: d: a // { ${ak d} = (a.${ak d} or [ ]) ++ [ (ak (keyOf n)) ]; }) acc (depsOf n)
      ) { } order;
    in
    foldl' (
      acc: n:
      let
        k = ak (keyOf n);
        v = foldl' (m: u: if acc.${u} + 1 > m then acc.${u} + 1 else m) 0 (users.${k} or [ ]);
      in
      seq v (acc // { ${k} = v; })
    ) { } (reverseList order);

  # a rank that ascends along every edge (depth) or descends along it (height), ties by key
  # DESCENDING: topological, and a function of the node set, so clauses 1 and 2 hold
  perturb =
    mode: keyOf: lessThan: depsOf: order:
    let
      up = mode == "P0";
      rank = (if up then depthOf else heightOf) keyOf depsOf order;
    in
    sort (
      a: b:
      let
        ka = keyOf a;
        kb = keyOf b;
        ra = rank.${ak ka};
        rb = rank.${ak kb};
      in
      if ra == rb then
        lessThan kb ka
      else if up then
        ra < rb
      else
        ra > rb
    ) order;

  perturbed = mode: {
    topoOrder =
      opts: data:
      let
        r = genGraph.topoOrder opts data;
        keyOf = opts.keyOf or (n: n);
      in
      if r.ok or false then
        r
        // {
          order = perturb mode keyOf (opts.lessThan or builtins.lessThan) (
            n: map keyOf (data.edges n)
          ) r.order;
        }
      else
        r;
    phaseOrder =
      entries:
      let
        names = attrNames entries;
      in
      perturb mode (n: n) builtins.lessThan (
        n: (entries.${n}.after or [ ]) ++ filter (t: elem n (entries.${t}.before or [ ])) names
      ) (genGraph.phaseOrder entries);
  };

  here = readDir ./.;
  reach = filter (
    f:
    f != self
    && here.${f} == "regular"
    && builtins.match ".*\\.nix" f != null
    && (
      hasInfix "topoOrder" (readFile (./. + "/${f}")) || hasInfix "phaseOrder" (readFile (./. + "/${f}"))
    )
  ) (attrNames here);

  cellsUnder =
    mode:
    concatMap (
      f:
      let
        tests =
          ((import (./. + "/${f}") (args // { genGraph = genGraph // perturbed mode; })).flake or { }).tests
            or { };
      in
      concatMap (
        suite:
        map (name: {
          name = "${suite}.${name}";
          cell = tests.${suite}.${name};
        }) (filter (n: builtins.substring 0 4 n == "test") (attrNames tests.${suite}))
      ) (attrNames tests)
    ) reach;
  passes =
    c:
    let
      r = tryEval (
        let
          e = c.cell.expr == c.cell.expected;
        in
        seq e e
      );
    in
    r.success && r.value;
  redOf = cells: map (c: c.name) (filter (c: !(passes c)) cells);
  cells0 = cellsUnder "P0";
  red0 = redOf cells0;
  red4 = redOf (cellsUnder "P4");
  red = red0 ++ filter (n: !(elem n red0)) red4;
  names = map (c: c.name) cells0;
  isDetector = hasInfix "change-detector";

  # the declaration itself, read off the shipped source (the slice precedent is
  # `test-topo-ready-set-heap-is-leftist`), whitespace runs squeezed to one space so a prose
  # reflow that wraps a clause does not read as its absence. Anchors carry no regex
  # metacharacter, since `split` reads its pattern as a regex.
  flat =
    s: builtins.concatStringsSep " " (filter builtins.isString (builtins.split "[[:space:]]+" s));
  orderSrc = flat (readFile ../../lib/order.nix);
  readmeSrc = flat (readFile ../../README.md);
  clauses = [
    "TOPOLOGICALITY — PROMISED"
    "PERMUTATION-INDEPENDENCE — PROMISED"
    "WHICH LINEAR EXTENSION — DECLARED AND PINNED, NOT NORMATIVE"
  ];
in
{
  flake.tests.order-contract-fence = {
    test-order-contract-fence = {
      expr = {
        missingClauses = filter (c: !(hasInfix c orderSrc)) clauses;
        missingReadmeClauses = filter (c: !(hasInfix c readmeSrc)) clauses;
        reachesOrderSuite = elem "order.nix" reach;
        cellCount = names != [ ];
        perturbationsMove = red0 != [ ] && red4 != [ ];
        unmarkedRed = filter (n: !(isDetector n)) red;
        deadDetectors = filter (n: isDetector n && !(elem n red)) names;
      };
      expected = {
        missingClauses = [ ];
        missingReadmeClauses = [ ];
        reachesOrderSuite = true;
        cellCount = true;
        perturbationsMove = true;
        unmarkedRed = [ ];
        deadDetectors = [ ];
      };
    };
  };
}
