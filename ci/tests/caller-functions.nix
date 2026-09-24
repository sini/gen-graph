# ── EVERY OTHER CALLER FUNCTION'S RESULT IS REFUSED WHERE IT IS READ (den-hoag-hekcx) ───────────
# `edges` (den-hoag-0mqv1) and the query's functions (den-hoag-pqp4z) were the first two
# populations. The rest of the published surface applies `pred`, `prune`, `parent`, `succ`,
# `lessThan`, `keyOf`, `key`, `expand`, `project`, `itemKey`, `step`, `refusal`, `scan`,
# `isRegistered`, `childBearing`, `isNode`, `structuralAttributesOf` and `perLabel`'s members, and
# applies `nodeData`, `resolve`, `emit`, `combine` and `valueOf` without reading their results.
# Unguarded, a result of the wrong type aborted past `tryEval`, a non-function aborted on its first
# application, a binary function's under-applied first result aborted on its second, and
# `materializeParents` carried a structured `parent` result into its answer at exit 0. The
# constructions are `_fixtures/caller-functions.nix`, and the messages are pinned on `testsError`
# (`ci/tests-error.nix`, `caller-functions`).
{ genGraph, ... }:
let
  inherit (import ./_fixtures/caller-functions.nix { inherit genGraph; })
    E
    g
    surfaces
    lawful
    malformed
    shapes
    binary
    passThrough
    passLawful
    ;
  G = genGraph;
  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  admittedWith =
    fs: builtins.filter (k: admitted (surfaces.${k} fs.${k})) (builtins.attrNames surfaces);
  admittedAll = f: builtins.filter (k: admitted (surfaces.${k} f)) (builtins.attrNames surfaces);
in
{
  flake.tests.caller-functions = {
    test-every-caller-function-refuses-a-malformed-result-catchably = {
      expr = admittedWith malformed;
      # fromRegistry passes parent's result through; ancestorsOf downstream reads and refuses it
      expected = [ ];
    };
    test-every-caller-function-refuses-a-non-function-catchably = {
      expr = admittedAll 1;
      expected = [ ];
    };
    test-a-functor-that-is-not-callable-is-refused-catchably = {
      expr = admittedAll { __functor = 1; };
      expected = [ ];
    };
    # the shapes a result can be wrong in beyond its top-level type, one per site that reads deeper
    test-a-malformed-result-shape-is-refused-catchably = {
      expr = builtins.filter (k: admitted shapes.${k}) (builtins.attrNames shapes);
      expected = [ ];
    };
    # `materializeParents` carried a structured `parent` result into its answer at exit 0
    test-materializeParents-refuses-a-structured-parent-rather-than-answering = {
      expr = {
        set = admitted (surfaces.materializeParents (_: { }));
        list = admitted (surfaces.materializeParents (_: [ "a" ]));
        function = admitted (surfaces.materializeParents (_: _: "a"));
      };
      expected = {
        set = false;
        list = false;
        function = false;
      };
    };
    # a binary function's first application must return a function, or the second aborts
    test-an-under-applied-binary-function-is-refused-catchably = {
      expr = builtins.filter (k: admitted binary.${k}) (builtins.attrNames binary);
      expected = [ ];
    };
    # a function applied and never read owes a door all the same
    test-a-pass-through-function-that-is-not-callable-is-refused-catchably = {
      expr =
        map (f: builtins.filter (k: admitted (passThrough.${k} f)) (builtins.attrNames passThrough))
          [
            1
            { __functor = 1; }
          ];
      expected = [
        [ ]
        [ ]
      ];
    };
    # CONTROL for the two cells above: every pass-through construction answers a lawful function,
    # and the binary sites' lawful arms are the lawful control below
    test-every-pass-through-construction-answers-a-lawful-function = {
      expr = builtins.mapAttrs (k: c: c passLawful.${k}) passThrough;
      expected = {
        select-nodeData = [ "a" ];
        expandPreorder-resolve = [
          "a"
          "b"
          "c"
        ];
        expandPreorder-emit = [
          "a"
          "b"
          "c"
        ];
        queryFold-combine = 2;
        queryFold-valueOf = 2;
      };
    };
    # CONTROL: the lawful function answers at every construction, so the refusals above are the
    # guards and not a broken fixture
    test-every-construction-answers-a-lawful-function = {
      expr = {
        admitted = builtins.length (admittedWith lawful);
        total = builtins.length (builtins.attrNames surfaces);
        refused = builtins.filter (k: !admitted (surfaces.${k} lawful.${k})) (builtins.attrNames surfaces);
        select = surfaces.select lawful.select;
        ancestorsOf = surfaces.ancestorsOf lawful.ancestorsOf;
        materializeParents = surfaces.materializeParents lawful.materializeParents;
        # a scalar parent is carried, as `nodeKey` keeps every scalar where the body does not key it.
        # ★ DEPENDS ON den-hoag-3w9e7's node-id ruling: if a node id is ruled a string, this arm
        # narrows to a refusal, and its flip is that ruling landing, not a regression.
        materializeParentsScalar = surfaces.materializeParents (_: 1);
      };
      expected = {
        admitted = 30;
        total = 31;
        select = [ "a" ];
        ancestorsOf = [
          "b"
          "a"
        ];
        materializeParents = {
          b = "a";
          c = "b";
        };
        materializeParentsScalar = {
          a = 1;
          b = 1;
          c = 1;
        };
        # its lawful arm is the caller's own refusal, thrown at the cap: refused, catchably
        refused = [ "fixpoint-refusal" ];
      };
    };
    # NO EARLIER: a function the surface never applies is never refused
    test-an-unapplied-function-is-not-refused = {
      expr = {
        select = G.select (g // { nodes = [ ]; }) 1;
        topoOrder = G.topoOrder {
          nodes = [ "a" ];
          edges = _: [ ];
          lessThan = 1;
        };
        # the door is lazy: a pred that never forces its argument never applies `nodeData`
        selectNodeData = G.select (g // { nodeData = 1; }) (_: true);
        fixpoint = G.fixpoint {
          seed = E;
          step = x: x;
          refusal = 1;
        };
      };
      expected = {
        select = [ ];
        topoOrder = {
          ok = true;
          order = [ "a" ];
        };
        selectNodeData = [
          "a"
          "b"
          "c"
        ];
        fixpoint = E;
      };
    };
  };
}
