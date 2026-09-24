# One reachability walk over a chain of n nodes, for `walks-cost.sh` to read under
# NIX_SHOW_STATS. Evaluates to the answer's length; `--strict` forces the whole answer, so a
# walk that has not run cannot be priced as one that allocated nothing.
#
# Two controls ride beside the four walks, because a ratio is only evidence if the
# instrument is shown both to read flat where the cost is flat and to read quadratic where
# it is quadratic:
#   `materializeParents` — no per-step `//`, so its copies must read FLAT across the span.
#   `quadraticVisited`  — the visited set the walks used to carry, extended by `//` at each
#                         step (in a `foldl'`, not a recursion, so it has no depth ceiling of
#                         its own), so its copies must read QUADRATIC across the span.
{
  arm,
  n,
}:
let
  # `default.nix`'s prelude shim, spelled out as `canreach-exit.nix` does.
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

  nm = i: "n${toString i}";
  idx = id: builtins.fromJSON (builtins.substring 1 20 id);
  edges = id: if idx id + 1 < n then [ (nm (idx id + 1)) ] else [ ];
  parent = id: if idx id == 0 then null else nm (idx id - 1);

  arms = {
    expandPreorder =
      (g.expandPreorder {
        roots = [ "n0" ];
        key = f: f;
        inherit edges;
      }).nodes;
    foldReach =
      (g.foldReach {
        roots = [ { to = "n0"; } ];
        edges = id: map (t: { to = t; }) (edges id);
        target = e: e.to;
        project = e: [ e.to ];
        itemKey = i: i;
      }).nodes;
    # a scalar accumulator isolates the core's own cost from the caller's
    foldPreorder =
      builtins.attrNames
        (g.foldPreorder {
          roots = [ "n0" ];
          key = f: f;
          acc = 0;
          expand = a: f: {
            acc = a + 1;
            children = edges f;
          };
        }).visited;
    ancestorsOf = g.ancestorsOf { inherit parent; } (nm (n - 1));
    materializeParents = builtins.attrNames (
      g.materializeParents {
        nodes = builtins.genList nm n;
        inherit parent;
      }
    );
    quadraticVisited = builtins.attrNames (
      builtins.foldl' (
        s: i:
        let
          s' = s // {
            ${nm i} = true;
          };
        in
        builtins.seq (builtins.attrNames s') s'
      ) { } (builtins.genList (i: i) n)
    );
  };
in
builtins.length arms.${arm}
