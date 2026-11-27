# ── THE ROOTED `lowlink` (`lowlink { root; } g`): THE CYCLIC SET AND A DEPENDENCY ORDER FROM THE ONE RUN ──
# `order` lists every node once, each strongly connected component's members together and each component
# after every component it reaches. On a DAG it is the depth-first FINISHING order of a search from
# `root`, restarting at each unvisited node in key order, expanding successors in `edges` list order;
# `root = null` is key order alone. `cyclic` is `cycles` on the same graph. Without `root`
# (`lowlink { } g`) the record is the partition record. The refusals are on `testsError`
# (`lowlink-root`, and the rooted rows of `lowlink-domain`).
{ genGraph, ... }:
let
  G = genGraph;
  acc = es: {
    nodes = builtins.attrNames es;
    edges = k: es.${k};
  };
  rooted = root: a: G.lowlink { inherit root; } a;
  orderOf = root: es: (rooted root (acc es)).order;
  graphs = {
    diamond = {
      a = [
        "b"
        "c"
      ];
      b = [ "d" ];
      c = [ "d" ];
      d = [ ];
    };
    diamondCB = {
      a = [
        "c"
        "b"
      ];
      b = [ "d" ];
      c = [ "d" ];
      d = [ ];
    };
    self = {
      x = [ "x" ];
      y = [ ];
    };
    twoCycle = {
      p = [ "q" ];
      q = [
        "p"
        "r"
      ];
      r = [ ];
    };
    disconnected = {
      m = [ "n" ];
      n = [ ];
      u = [ "v" ];
      v = [ ];
    };
    # key order disagrees with the root-first order
    lateKey = {
      z = [
        "b"
        "a"
      ];
      a = [ ];
      b = [ "c" ];
      c = [ ];
    };
    # a 3-cycle that reaches a 2-cycle, below a root
    chainOfCycles = {
      r = [ "a" ];
      a = [ "b" ];
      b = [ "c" ];
      c = [
        "a"
        "x"
      ];
      x = [ "y" ];
      y = [ "x" ];
    };
  };
  # the contract on any digraph: `order` is a permutation of `nodes`, each SCC (the plain record's
  # `sccOf`) is contiguous, and across every edge the target's component comes first
  invariantsHold =
    root: es:
    let
      order = orderOf root es;
      sccOf = (G.lowlink { } (acc es)).sccOf;
      pos = builtins.listToAttrs (
        builtins.genList (i: {
          name = builtins.elemAt order i;
          value = i;
        }) (builtins.length order)
      );
      tags = map (v: sccOf.${v}) order;
      contiguous =
        (builtins.foldl'
          (st: t: {
            ok = st.ok && (t == st.cur || !(st.done ? ${t}));
            cur = t;
            done = st.done // (if st.cur == null then { } else { ${st.cur} = true; });
          })
          {
            ok = true;
            cur = null;
            done = { };
          }
          tags
        ).ok;
    in
    builtins.sort builtins.lessThan order == builtins.sort builtins.lessThan (builtins.attrNames es)
    && contiguous
    && builtins.all (v: builtins.all (w: sccOf.${w} == sccOf.${v} || pos.${w} < pos.${v}) es.${v}) (
      builtins.attrNames es
    );
  cyclicGraphs = {
    inherit (graphs) self twoCycle chainOfCycles;
  };
  perms =
    xs:
    if xs == [ ] then
      [ [ ] ]
    else
      builtins.concatMap (x: map (p: [ x ] ++ p) (perms (builtins.filter (y: y != x) xs))) xs;
  distinctOrders =
    root: es:
    builtins.attrNames (
      builtins.listToAttrs (
        map (ns: {
          name =
            builtins.toJSON
              (G.lowlink { inherit root; } {
                nodes = ns;
                edges = k: es.${k};
              }).order;
          value = null;
        }) (perms (builtins.attrNames es))
      )
    );
in
{
  flake.tests.rooted-lowlink = {
    test-order-on-fixed-graphs = {
      expr = {
        diamondA = orderOf "a" graphs.diamond;
        diamondCBA = orderOf "a" graphs.diamondCB;
        diamondB = orderOf "b" graphs.diamond;
        diamondNull = orderOf null graphs.diamond;
        disconnectedU = orderOf "u" graphs.disconnected;
        disconnectedNull = orderOf null graphs.disconnected;
        lateKeyZ = orderOf "z" graphs.lateKey;
        lateKeyNull = orderOf null graphs.lateKey;
        selfY = orderOf "y" graphs.self;
        empty =
          (rooted null {
            nodes = [ ];
            edges = _: [ ];
          }).order;
      };
      expected = {
        diamondA = [
          "d"
          "b"
          "c"
          "a"
        ];
        diamondCBA = [
          "d"
          "c"
          "b"
          "a"
        ];
        diamondB = [
          "d"
          "b"
          "c"
          "a"
        ];
        diamondNull = [
          "d"
          "b"
          "c"
          "a"
        ];
        disconnectedU = [
          "v"
          "u"
          "n"
          "m"
        ];
        disconnectedNull = [
          "n"
          "m"
          "v"
          "u"
        ];
        lateKeyZ = [
          "c"
          "b"
          "a"
          "z"
        ];
        lateKeyNull = [
          "a"
          "c"
          "b"
          "z"
        ];
        selfY = [
          "y"
          "x"
        ];
        empty = [ ];
      };
    };
    # the CONTRACT on the cyclic graphs, from every root: a permutation, each component contiguous, each
    # component after every component it reaches. Members inside a component are in no promised order.
    test-order-invariants-on-cyclic-graphs = {
      expr = builtins.mapAttrs (
        _: es: builtins.all (r: invariantsHold r es) ([ null ] ++ builtins.attrNames es)
      ) cyclicGraphs;
      expected = builtins.mapAttrs (_: _: true) cyclicGraphs;
    };
    # CHARACTERISATION, pinned, not promised: today's member order inside each component. A conforming
    # change to the run may move it; the invariants cell above is the contract.
    test-order-on-cyclic-graphs-characterisation = {
      expr = {
        twoCycleP = orderOf "p" graphs.twoCycle;
        chainOfCyclesR = orderOf "r" graphs.chainOfCycles;
      };
      expected = {
        twoCycleP = [
          "r"
          "p"
          "q"
        ];
        chainOfCyclesR = [
          "x"
          "y"
          "a"
          "b"
          "c"
          "r"
        ];
      };
    };
    # the same derivation as `cycles`, on every fixed graph and from every root
    test-cyclic-is-cycles = {
      expr = builtins.mapAttrs (
        _: es:
        builtins.all (r: (rooted r (acc es)).cyclic == G.cycles (acc es)) (
          [ null ] ++ builtins.attrNames es
        )
      ) graphs;
      expected = builtins.mapAttrs (_: _: true) graphs;
    };
    # a function of the node SET: one order over every permutation of the `nodes` list
    test-order-is-independent-of-the-nodes-permutation = {
      expr = builtins.mapAttrs (
        _: es:
        map builtins.length [
          (distinctOrders null es)
          (distinctOrders (builtins.head (builtins.attrNames es)) es)
        ]
      ) graphs;
      expected = builtins.mapAttrs (_: _: [
        1
        1
      ]) graphs;
    };
    # the successor rule is real: the edge-list order moves the order
    test-order-follows-the-edge-list = {
      expr = orderOf "a" graphs.diamond != orderOf "a" graphs.diamondCB;
      expected = true;
    };
    # without `root` the record is the partition record, and `{ root = … }` adds exactly two fields
    test-plain-record-is-the-partition-record = {
      expr = {
        plain = builtins.attrNames (G.lowlink { } (acc graphs.diamond));
        rooted = builtins.attrNames (rooted "a" (acc graphs.diamond));
        partitionUnchanged =
          builtins.removeAttrs (rooted "p" (acc graphs.twoCycle)) [
            "cyclic"
            "order"
          ] == G.lowlink { } (acc graphs.twoCycle);
      };
      expected = {
        plain = [
          "bottomUp"
          "condEdges"
          "depth"
          "members"
          "reps"
          "sccOf"
          "sccs"
        ];
        rooted = [
          "bottomUp"
          "condEdges"
          "cyclic"
          "depth"
          "members"
          "order"
          "reps"
          "sccOf"
          "sccs"
        ];
        partitionUnchanged = true;
      };
    };
    # only the `lowlink` door roots: a `root` field on another partition surface's open record is ignored
    test-root-field-ignored-outside-lowlink = {
      expr = {
        condensation =
          G.condensation ((acc graphs.diamond) // { root = "zz"; }) == G.condensation (acc graphs.diamond);
        cycles = G.cycles ((acc graphs.twoCycle) // { root = "zz"; });
      };
      expected = {
        condensation = true;
        cycles = [
          "p"
          "q"
        ];
      };
    };
  };
}
