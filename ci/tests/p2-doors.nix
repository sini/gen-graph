# P2 (den-hoag-7gp66, spec §p2.5): what the door table (`doors.nix`) cannot say by construction.
#
# G3 — an options step forms a composition value. For every options step whose option is
# observable in its own result, the partially applied `f = door opts` (1) AGREES with the direct
# full call, and (2) DIFFERS from the same door under `{ }`: an options step that ignored its
# options, or only read them behind the subject, reds (2) (spec K3; a same-term equality alone is
# vacuous by referential transparency). `ancestorsOf`'s one option is retired, so it has no
# observable option and G4 (`doors.nix`) alone stands for it.
{ genGraph, ... }:
let
  G = genGraph;
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  chain = {
    nodes = [
      "a"
      "b"
      "c"
    ];
    edges =
      id:
      {
        a = [ "b" ];
        b = [ "c" ];
      }
      .${id} or [ ];
  };
  tri = chain // {
    edges =
      id:
      {
        a = [
          "b"
          "c"
        ];
        b = [ "c" ];
      }
      .${id} or [ ];
  };

  # Each row: `partial` is the options step applied and BOUND before any operand, `full` the same
  # call written out whole, `zero` the door under `{ }`; `obs` projects what the option changes.
  rows = {
    pathsBetween =
      let
        o = {
          maxDepth = 1;
        };
        partial = G.pathsBetween o;
      in
      {
        obs = ok;
        partial = partial chain "a" "c";
        full = G.pathsBetween o chain "a" "c";
        zero = G.pathsBetween { } chain "a" "c";
      };
    fixpoint =
      let
        o = {
          maxIter = 1;
        };
        # converges on its second round, so the cap of 1 refuses and the default does not
        step = m: m // { a = [ "b" ]; };
        partial = G.fixpoint o;
      in
      {
        obs = ok;
        partial = partial step { };
        full = G.fixpoint o step { };
        zero = G.fixpoint { } step { };
      };
    topoOrder =
      let
        o = {
          lessThan = a: b: a > b;
        };
        g = {
          nodes = [
            "a"
            "b"
          ];
          edges = _: [ ];
        };
        partial = G.topoOrder o;
      in
      {
        obs = r: r.order;
        partial = partial g;
        full = G.topoOrder o g;
        zero = G.topoOrder { } g;
      };
    mkGraph =
      let
        o.edges = [
          {
            from = "a";
            to = "b";
          }
        ];
      in
      {
        obs = g: g.nodes;
        partial = G.mkGraph o;
        full = G.mkGraph {
          edges = [
            {
              from = "a";
              to = "b";
            }
          ];
        };
        zero = G.mkGraph { };
      };
    fromRegistry =
      let
        o.parent = _: e: e.up or null;
        reg = {
          a = { };
          b.up = "a";
        };
        partial = G.fromRegistry o;
      in
      {
        obs = g: g.parent "b";
        partial = partial (G.field "deps") reg;
        full = G.fromRegistry o (G.field "deps") reg;
        zero = G.fromRegistry { } (G.field "deps") reg;
      };
    transitiveClosure =
      let
        o.maxIter = 1;
        partial = G.transitiveClosure o;
      in
      {
        obs = ok;
        partial = partial chain;
        full = G.transitiveClosure o chain;
        zero = G.transitiveClosure { } chain;
      };
    dependents =
      let
        o.maxIter = 1;
        partial = G.dependents o;
      in
      {
        obs = ok;
        partial = partial chain "c";
        full = G.dependents o chain "c";
        zero = G.dependents { } chain "c";
      };
    condensationClosure =
      let
        o.maxIter = 1;
        partial = G.condensationClosure o;
      in
      {
        obs = ok;
        partial = partial chain;
        full = G.condensationClosure o chain;
        zero = G.condensationClosure { } chain;
      };
    # out-degree 2 at `a`: the reduction forces its closure only where a node has two successors
    transitiveReduction =
      let
        o.maxIter = 1;
        partial = G.transitiveReduction o;
      in
      {
        obs = ok;
        partial = partial tri;
        full = G.transitiveReduction o tri;
        zero = G.transitiveReduction { } tri;
      };
    seededFixpoint =
      let
        o.maxIter = 0;
        r = {
          seed = { };
          frontier = {
            a = [ "b" ];
          };
          step = _: _: { };
        };
        partial = G.seededFixpoint o;
      in
      {
        obs = ok;
        partial = partial r;
        full = G.seededFixpoint o r;
        zero = G.seededFixpoint { } r;
      };
    foldPreorder =
      let
        o.visited = {
          a = true;
        };
        r = {
          roots = [ "a" ];
          key = f: f;
          expand = acc: f: {
            acc = acc ++ [ f ];
          };
          acc = [ ];
        };
        partial = G.foldPreorder o;
      in
      {
        obs = res: res.acc;
        partial = partial r;
        full = G.foldPreorder o r;
        zero = G.foldPreorder { } r;
      };
    expandPreorder =
      let
        o.emit = f: _: "seen:${f}";
        r = {
          roots = [ "a" ];
          key = f: f;
          inherit (chain) edges;
        };
        partial = G.expandPreorder o;
      in
      {
        obs = res: res.nodes;
        partial = partial r;
        full = G.expandPreorder o r;
        zero = G.expandPreorder { } r;
      };
    foldReach =
      let
        o.nodes0 = [ "z" ];
        r = {
          roots = [ ];
          inherit (chain) edges;
          target = e: e;
          project = _: [ ];
          itemKey = i: i;
        };
        partial = G.foldReach o;
      in
      {
        obs = res: res.nodes;
        partial = partial r;
        full = G.foldReach o r;
        zero = G.foldReach { } r;
      };
    fromScan =
      let
        o.nodeData = {
          a.tag = 1;
        };
        r = {
          items = [
            {
              id = "a";
              value = [ ];
            }
          ];
          scan = v: v;
          project = x: x;
        };
        partial = G.fromScan o;
      in
      {
        obs = g: g.nodeData "a";
        partial = partial r;
        full = G.fromScan o r;
        zero = G.fromScan { } r;
      };
  };

in
{
  flake.tests.p2-doors = {
    # G3 (1): the partial application, bound first, answers what the full call answers.
    test-g3-the-partial-application-agrees-with-the-full-call = {
      expr = builtins.mapAttrs (_: r: r.obs r.partial == r.obs r.full) rows;
      expected = builtins.mapAttrs (_: _: true) rows;
    };
    # G3 (2): the option is carried — the answer differs from the same door under `{ }`.
    test-g3-a-non-default-option-changes-the-answer = {
      expr = builtins.mapAttrs (_: r: r.obs r.partial != r.obs r.zero) rows;
      expected = builtins.mapAttrs (_: _: true) rows;
    };

  };
}
