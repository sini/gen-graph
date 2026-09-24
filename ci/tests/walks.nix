# walks.nix — the reachability walks (`expandPreorder`, `foldReach`, `foldPreorder`,
# `ancestorsOf`) run past every ceiling the old self-recursive construction had, and keep
# their exact answers (den-hoag-2t0sj, den-hoag-ngtxq).
#
# The fan-out and depth cells are sized past the measured old boundaries: on `00fe4bf`
# `expandPreorder` aborted with CSTACK on a 40,001 star (uncatchable: the suite process
# itself died), `foldReach` with max-call-depth on an 8,001 star, and a 20,000 chain met the
# named depth refusals. They read `len`, a `deepSeq`'d length, so a lazy answer cannot pass
# on a walk that has not run.
#
# The pinned-order digest serialises every surface's full answer on 40 pseudo-random cyclic
# graphs (self-loops, diamonds, duplicate roots and successors, keyless frames, seeded
# visited sets, `null` item keys, a `seen0` with a non-`true` value). The expected digest is
# the old recursive walks' answer on the same corpus, so it pins pre-order, sibling order,
# first-occurrence and seed pruning to the construction this one replaced.
{ genGraph, ... }:
let
  G = genGraph;
  nm = i: "n${toString i}";
  idx = id: builtins.fromJSON (builtins.substring 1 20 id);
  chainOf = n: id: if idx id + 1 < n then [ (nm (idx id + 1)) ] else [ ];
  starOf = n: id: if id == "n0" then builtins.genList (i: nm (i + 1)) (n - 1) else [ ];
  ep =
    edges:
    (G.expandPreorder {
      roots = [ "n0" ];
      key = f: f;
      inherit edges;
    }).nodes;
  fr =
    edges:
    (G.foldReach {
      roots = [ { to = "n0"; } ];
      edges = id: map (t: { to = t; }) (edges id);
      target = e: e.to;
      project = e: [ e.to ];
      itemKey = i: i;
    }).nodes;
  fp =
    edges:
    (G.foldPreorder {
      roots = [ "n0" ];
      key = f: f;
      acc = 0;
      expand = a: f: {
        acc = a + 1;
        children = edges f;
      };
    }).acc;
  len = xs: builtins.length (builtins.deepSeq xs xs);

  # Node i has out-degree h(seed/i) mod 5 over targets h(seed/i/j) mod 150, h being the first
  # 7 hex digits of sha256.
  h = s: (builtins.fromTOML "x = 0x${builtins.substring 0 7 (builtins.hashString "sha256" s)}").x;
  md = a: b: a - (a / b) * b;
  n = 150;
  graph = seed: {
    edges =
      id:
      builtins.genList (j: nm (md (h "${toString seed}/${toString (idx id)}/${toString j}") n)) (
        md (h "${toString seed}/${toString (idx id)}") 5
      );
    parent =
      id:
      let
        v = h "${toString seed}/p/${id}";
      in
      if md v 7 == 0 then null else nm (md v n);
    anon = id: md (h "${toString seed}/a/${id}") 11 == 0;
    seeded = {
      ${nm (md (h "${toString seed}/s") n)} = true;
    };
    roots = [
      "n0"
      (nm (md seed n))
      "n0"
    ];
  };
  one =
    seed:
    let
      g = graph seed;
    in
    {
      ep = G.expandPreorder {
        inherit (g) roots edges;
        key = f: f;
        emit = f: p: "${f}:${toString (builtins.length (g.edges p))}";
      };
      epSeed = G.expandPreorder {
        inherit (g) roots edges;
        key = f: f;
        seen0 = g.seeded;
        nodes0 = [ "pre" ];
      };
      fr = G.foldReach {
        roots = map (t: {
          to = t;
          l = "r";
        }) g.roots;
        edges =
          id:
          map (t: {
            to = t;
            l = id;
          }) (g.edges id);
        target = e: e.to;
        project =
          e:
          [
            "${e.to}"
            "${e.l}>${e.to}"
          ]
          ++ (if g.anon e.to then [ { anon = e.to; } ] else [ ]);
        itemKey = i: if builtins.isAttrs i then null else i;
        visited0 = g.seeded;
        seen0 = {
          "n1" = "seed";
        };
        nodes0 = [ "pre" ];
      };
      # Keyless frames: `{ id; k; }` has a `null` key when `anon id`, so it expands every time;
      # its children are made keyed, which keeps the unfolding finite.
      fp = G.foldPreorder {
        roots = map (id: {
          inherit id;
          k = true;
        }) g.roots;
        key = f: if f.k && g.anon f.id then null else f.id;
        acc = {
          xs = [ ];
          c = 0;
        };
        visited = g.seeded;
        expand = a: f: {
          acc = {
            xs = a.xs ++ [ f.id ];
            c = a.c + 1;
          };
          children = map (id: {
            inherit id;
            k = !(f.k && g.anon f.id);
          }) (g.edges f.id);
        };
      };
      anc = builtins.genList (i: G.ancestorsOf { inherit (g) parent; } (nm i)) 20;
    };
in
{
  flake.tests.walks = {
    test-star-fanout-expandPreorder = {
      expr = len (ep (starOf 40001));
      expected = 40001;
    };
    test-star-fanout-foldReach = {
      expr = len (fr (starOf 8001));
      expected = 8001;
    };
    test-chain-depth-all-four = {
      expr = {
        ep = len (ep (chainOf 20000));
        fr = len (fr (chainOf 20000));
        fp = fp (chainOf 20000);
        anc = len (
          G.ancestorsOf { parent = id: if idx id == 0 then null else nm (idx id - 1); } (nm 19999)
        );
      };
      expected = {
        ep = 20000;
        fr = 20000;
        fp = 20000;
        anc = 19999;
      };
    };
    test-pinned-order-digest = {
      expr = builtins.hashString "sha256" (builtins.toJSON (builtins.genList one 40));
      expected = "81a49b7632e58e5ef7bb605507799910f93ffcf3cde73a2ab1f1761ebfc39f5e";
    };
  };
}
