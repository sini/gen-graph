# P2 (den-hoag-7gp66, spec §p2.5): what the door table (`doors.nix`) cannot say by construction.
#
# G3 — an options step forms a composition value. For every options step whose option is
# observable in its own result, the partially applied `f = door opts` (1) AGREES with the direct
# full call, and (2) DIFFERS from the same door under `{ }`: an options step that ignored its
# options, or only read them behind the subject, reds (2) (spec K3; a same-term equality alone is
# vacuous by referential transparency). `ancestorsOf`'s one option is retired, so it has no
# observable option and G4 (`doors.nix`) alone stands for it.
#
# den-hoag-nvrl1 — the query family's options are ONE closed set in every mode: an unknown option
# is refused catchably at `query opts`'s WHNF whatever the mode, and a missing record field is
# refused catchably at the record's own application, in every mode. The messages are pinned on
# `testsError` (`p2-query-closure`).
{ genGraph, ... }:
let
  G = genGraph;
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  formed = v: (builtins.tryEval (builtins.seq v true)).success;
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
  labeled = G.labeledFrom {
    x = chain.edges;
  } chain.nodes;
  q = {
    graph = labeled;
    from = "a";
    follow = G.regex.parse "x*";
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
    regex-parseWith =
      let
        o.maxLength = 1;
        partial = G.regex.parseWith o;
      in
      {
        obs = ok;
        partial = partial "x*";
        full = G.regex.parseWith o "x*";
        zero = G.regex.parseWith { } "x*";
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
    queryArrivals =
      let
        o.where = id: id != "a";
        r = q // {
          advance = s: s.distance + 1;
        };
        partial = G.queryArrivals o;
      in
      {
        obs = map (a: a.node);
        partial = partial r;
        full = G.queryArrivals o r;
        zero = G.queryArrivals { } r;
      };
    queryFold =
      let
        o.valueOf = id: "<${id}>";
        partial = G.queryFold o;
      in
      {
        obs = s: s;
        partial = partial (a: v: a + v) "" q;
        full = G.queryFold o (a: v: a + v) "" q;
        zero = G.queryFold { } (a: v: a + v) "" q;
      };
    query =
      let
        o.mode = "paths";
        partial = G.query o;
      in
      {
        obs = builtins.toJSON;
        partial = partial q;
        full = G.query o q;
        zero = G.query { } q;
      };
  };

  modes = {
    all = { };
    series = { };
    paths = { };
    visible.groupBy = a: a.node;
    layers = { };
    fixpoint = {
      empty = 0;
      combine = n: _: n + 1;
    };
  };
  unknown = "notAFieldOfThisDoor";
  withMode = m: modes.${m} // { mode = m; };
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

    # den-hoag-nvrl1: the same closed options set in every mode.
    test-nvrl1-an-unknown-option-is-refused-in-every-mode = {
      expr = builtins.mapAttrs (m: _: formed (G.query (withMode m // { ${unknown} = 1; }))) modes;
      expected = builtins.mapAttrs (_: _: false) modes;
    };
    test-nvrl1-a-missing-record-field-is-refused-in-every-mode = {
      expr = builtins.mapAttrs (
        m: _: formed (G.query (withMode m) (builtins.removeAttrs q [ "follow" ]))
      ) modes;
      expected = builtins.mapAttrs (_: _: false) modes;
    };
    test-nvrl1-an-option-on-the-record-is-refused-in-every-mode = {
      expr = builtins.mapAttrs (m: _: formed (G.query (withMode m) (q // { where = _: true; }))) modes;
      expected = builtins.mapAttrs (_: _: false) modes;
    };
    # The control: every mode answers the well-formed call, so the three cells above are not a
    # door that refuses everything.
    test-nvrl1-every-mode-answers-the-well-formed-call = {
      expr = builtins.mapAttrs (m: _: ok (G.query (withMode m) q)) modes;
      expected = builtins.mapAttrs (_: _: true) modes;
    };
    test-nvrl1-queryFold-refuses-an-unknown-option-and-a-missing-field = {
      expr = {
        unknown = formed (G.queryFold { ${unknown} = 1; });
        missing = formed (G.queryFold { } (a: _: a) 0 (builtins.removeAttrs q [ "graph" ]));
        control = ok (G.queryFold { } (a: _: a + 1) 0 q);
      };
      expected = {
        unknown = false;
        missing = false;
        control = true;
      };
    };
    # A mode's own required option, and an unknown mode, are refused when `query opts` is formed.
    test-nvrl1-a-mode-requirement-is-refused-at-the-options = {
      expr = {
        visible = formed (G.query { mode = "visible"; });
        fixpoint = formed (G.query { mode = "fixpoint"; });
        bogus = formed (G.query { mode = "bogus"; });
      };
      expected = {
        visible = false;
        fixpoint = false;
        bogus = false;
      };
    };
  };
}
