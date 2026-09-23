# ── A CALLER FUNCTION'S RESULT IS REFUSED WHERE IT IS CONSUMED (den-hoag-pqp4z) ───────────────
# `where`, `groupBy`, `advance`, `marksOf`, a mark's `admits` and `cyclicEdgesWhere`'s `p` are
# applied by the labeled surfaces and their results read. Unguarded, a result of the wrong type
# aborted past `tryEval` (`expected a Boolean but found an integer`), or — `advance` — was carried
# into the answer at exit 0. These cells assert every arm is refused CATCHABLY; the messages are
# pinned on `testsError` (`ci/tests-error.nix`, `caller-results`).
{ genGraph, ... }:
let
  inherit (genGraph)
    boundedBy
    cyclicEdgesWhere
    query
    queryArrivals
    regex
    ;
  x = regex.star (regex.lit "x");
  graph = {
    nodes = [
      "a"
      "b"
    ];
    labeledEdges =
      id:
      if id == "a" then
        [
          {
            label = "x";
            target = "b";
          }
        ]
      else
        [ ];
  };
  q =
    extra:
    query (
      {
        inherit graph;
        from = "a";
        follow = x;
      }
      // extra
    );
  arrivals =
    extra:
    queryArrivals (
      {
        inherit graph;
        from = "a";
        follow = x;
        advance = s: s.distance + 1;
      }
      // extra
    );
  bounded = marks: (boundedBy graph (_: marks)).withheld "a";
  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;

  # every walk mode, with a `where` returning an int and a `where` that is not a function
  whereArms = w: {
    all = q { where = w; };
    series = q {
      mode = "series";
      where = w;
    };
    paths = q {
      mode = "paths";
      where = w;
    };
    visible = q {
      mode = "visible";
      groupBy = a: a.node;
      where = w;
    };
    layers = q {
      mode = "layers";
      where = w;
    };
    fixpoint = q {
      mode = "fixpoint";
      empty = [ ];
      combine = a: b: a ++ [ b ];
      where = w;
    };
    arrivals = arrivals { where = w; };
  };
  otherArms = {
    advanceString = arrivals { advance = _: "far"; };
    groupByInt = q {
      mode = "visible";
      groupBy = _: 1;
    };
    marksOfInt = (boundedBy graph (_: 1)).labeledEdges "a";
    markInt = bounded [ 1 ];
    markNoAdmits = bounded [ { name = "m"; } ];
    admitsNotFunction = bounded [
      {
        name = "m";
        admits = 1;
      }
    ];
    admitsInt = bounded [
      {
        name = "m";
        admits = _: 1;
      }
    ];
    markNoName = bounded [ { admits = _: false; } ];
    pInt = cyclicEdgesWhere graph (_: 1);
    pNotFunction = cyclicEdgesWhere graph 1;
    # a set whose `__functor` is not a function is not callable, at every door incl. `edgesAt`
    whereFunctorInt = q {
      where = {
        __functor = 1;
      };
    };
    labeledEdgesFunctorInt = q {
      graph = graph // {
        labeledEdges = {
          __functor = 1;
        };
      };
    };
  };
  admittedOf = arms: builtins.filter (k: admitted arms.${k}) (builtins.attrNames arms);
in
{
  flake.tests.caller-results = {
    test-every-walk-mode-refuses-a-non-bool-where-catchably = {
      expr = admittedOf (whereArms (_: 1));
      expected = [ ];
    };
    test-every-walk-mode-refuses-a-non-function-where-catchably = {
      expr = admittedOf (whereArms 1);
      expected = [ ];
    };
    test-every-other-caller-function-result-is-refused-catchably = {
      expr = admittedOf otherArms;
      expected = [ ];
    };
    # CONTROL: the same constructions with lawful functions answer, so the refusals above are the
    # guards and not a broken fixture
    test-the-lawful-arms-answer = {
      expr = {
        where = admittedOf (whereArms (n: n == "b"));
        advance = map (a: a.distance) (arrivals { });
        withheld = bounded [
          {
            name = "m";
            admits = _: false;
          }
        ];
      };
      expected = {
        where = [
          "all"
          "arrivals"
          "fixpoint"
          "layers"
          "paths"
          "series"
          "visible"
        ];
        advance = [
          0
          1
        ];
        withheld = [
          {
            label = "x";
            target = "b";
            marks = [ "m" ];
          }
        ];
      };
    };
    # a mark's `name` is carried, never read for its type: gen-view's composition reports it as given
    test-a-mark-name-is-carried-unforced = {
      expr = bounded [
        {
          name = 1;
          admits = _: false;
        }
      ];
      expected = [
        {
          label = "x";
          target = "b";
          marks = [ 1 ];
        }
      ];
    };
  };
}
