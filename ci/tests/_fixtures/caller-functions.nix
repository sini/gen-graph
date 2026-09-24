# NOT A SUITE. The constructions `ci/tests/caller-functions.nix` asserts catchable and
# `ci/tests-error.nix` (`caller-functions`) pins by message, held once so both assert about the same
# objects. It sits under `_fixtures/` because the tree importer ignores any path with that segment.
{ genGraph }:
let
  G = genGraph;
  E = {
    a = [ "b" ];
    b = [ "c" ];
  };
  P = {
    b = "a";
    c = "b";
  };
  g = {
    nodes = [
      "a"
      "b"
      "c"
    ];
    edges = id: E.${id} or [ ];
    parent = id: P.${id} or null;
    nodeData = id: { v = id; };
  };
  okSucc = id: map (k: { key = k; }) (g.edges id);
  okExpand = acc: f: {
    acc = acc ++ [ f ];
    children = g.edges f;
  };
  okSa = _: { deps = [ "b" ]; };

  # one construction per caller function; `f` stands in for that function, every other one lawful
  surfaces = {
    select = f: G.select g f;
    reachableWhere = f: G.reachableWhere g "a" f;
    selectEdges = f: G.selectEdges f E;
    dependentsFrontier = f: G.dependentsFrontier g "c" f;
    ancestorsOf = f: G.ancestorsOf (g // { parent = f; }) "c";
    materializeParents = f: G.materializeParents (g // { parent = f; });
    reachableVia = f: G.reachableVia f "a";
    selfReachableVia = f: G.selfReachableVia f "a";
    topoOrder-lessThan =
      f:
      G.topoOrder {
        inherit (g) nodes edges;
        lessThan = f;
      };
    topoOrderKahn-lessThan =
      f:
      G.topoOrderKahn {
        inherit (g) nodes;
        edges = _: [ ];
        lessThan = f;
      };
    foldPreorder-key =
      f:
      G.foldPreorder {
        roots = [ "a" ];
        key = f;
        expand = okExpand;
        acc = [ ];
      };
    foldPreorder-expand =
      f:
      G.foldPreorder {
        roots = [ "a" ];
        key = x: x;
        expand = f;
        acc = [ ];
      };
    expandPreorder-key =
      f:
      G.expandPreorder {
        roots = [ "a" ];
        key = f;
        inherit (g) edges;
      };
    foldReach-target = f: reach { target = f; };
    foldReach-project = f: reach { project = f; };
    foldReach-itemKey = f: reach { itemKey = f; };
    fixpoint-step =
      f:
      G.fixpoint {
        seed = E;
        step = f;
      };
    fixpoint-refusal =
      f:
      G.fixpoint {
        seed = E;
        step = x: x;
        maxIter = 0;
        refusal = f;
      };
    seededFixpoint =
      f:
      G.seededFixpoint {
        seed = E;
        frontier = E;
        step = f;
      };
    fromScan-scan = f: scanned { scan = f; };
    fromScan-project = f: scanned { project = f; };
    mkNodeRef = f: G.mkNodeRef { isRegistered = f; } "a";
    nodeRefFindings = f: G.nodeRefFindings { isRegistered = f; } "a";
    mkEndpointProjection-childBearing = f: projection G.mkEndpointProjection { childBearing = f; } okSa;
    mkEndpointProjection-isNode = f: projection G.mkEndpointProjection { isNode = f; } okSa;
    mkEndpointProjection-structuralAttributesOf = f: projection G.mkEndpointProjection { } f;
    mkProjectionFindings-childBearing = f: projection G.mkProjectionFindings { childBearing = f; } okSa;
    mkProjectionFindings-isNode = f: projection G.mkProjectionFindings { isNode = f; } okSa;
    mkProjectionFindings-structuralAttributesOf = f: projection G.mkProjectionFindings { } f;
    labeledFrom = f: labeled { x = f; };
    fromRegistry-parent =
      f:
      G.ancestorsOf (G.fromRegistry {
        registry = {
          a = { };
          b.up = "a";
        };
        edges = G.field "deps";
        parent = f;
      }) "b";
  };
  reach =
    over:
    G.foldReach (
      {
        roots = [ { to = "a"; } ];
        edges = id: map (t: { to = t; }) (g.edges id);
        target = e: e.to;
        project = e: [ e.to ];
        itemKey = i: i;
      }
      // over
    );
  scanned =
    over:
    let
      r = G.fromScan (
        {
          items = [
            {
              id = "a";
              value = [ "b" ];
            }
          ];
          scan = v: v;
          project = r: r;
        }
        // over
      );
    in
    {
      inherit (r) nodes derivedEdges;
    };
  projection =
    mk: over: sa:
    mk (
      {
        childBearing = _: false;
        isNode = _: true;
      }
      // over
    ) sa "a";
  labeled =
    perLabel:
    (G.forgetLabels (
      G.labeledFrom {
        nodes = [
          "a"
          "b"
        ];
        inherit perLabel;
      }
    )).edges
      "a";

  # the lawful function for each construction, and a result of the wrong type at the same arity
  lawful = {
    select = d: d.v == "a";
    reachableWhere = _: true;
    selectEdges = _: _: true;
    dependentsFrontier = _: true;
    ancestorsOf = g.parent;
    materializeParents = g.parent;
    reachableVia = okSucc;
    selfReachableVia = okSucc;
    topoOrder-lessThan = a: b: a < b;
    topoOrderKahn-lessThan = a: b: a < b;
    foldPreorder-key = x: x;
    foldPreorder-expand = okExpand;
    expandPreorder-key = x: x;
    foldReach-target = e: e.to;
    foldReach-project = e: [ e.to ];
    foldReach-itemKey = i: i;
    fixpoint-step = x: x;
    fixpoint-refusal = _: "capped";
    seededFixpoint = _: _: { };
    fromScan-scan = v: v;
    fromScan-project = r: r;
    mkNodeRef = _: true;
    nodeRefFindings = _: true;
    mkEndpointProjection-childBearing = _: false;
    mkEndpointProjection-isNode = _: true;
    mkEndpointProjection-structuralAttributesOf = okSa;
    mkProjectionFindings-childBearing = _: false;
    mkProjectionFindings-isNode = _: true;
    mkProjectionFindings-structuralAttributesOf = okSa;
    labeledFrom = id: if id == "a" then [ "b" ] else [ ];
    fromRegistry-parent = _: e: e.up or null;
  };
  malformed = {
    select = _: 1;
    reachableWhere = _: 1;
    selectEdges = _: _: 1;
    dependentsFrontier = _: 1;
    ancestorsOf = _: { };
    materializeParents = _: { };
    reachableVia = _: 1;
    selfReachableVia = _: 1;
    topoOrder-lessThan = _: _: 1;
    topoOrderKahn-lessThan = _: _: 1;
    foldPreorder-key = _: { };
    foldPreorder-expand = _: _: 1;
    expandPreorder-key = _: { };
    foldReach-target = _: { };
    foldReach-project = _: 1;
    foldReach-itemKey = _: { };
    fixpoint-step = _: 1;
    fixpoint-refusal = _: 1;
    seededFixpoint = _: _: 1;
    fromScan-scan = _: 1;
    fromScan-project = _: { };
    mkNodeRef = _: 1;
    nodeRefFindings = _: 1;
    mkEndpointProjection-childBearing = _: 1;
    mkEndpointProjection-isNode = _: 1;
    mkEndpointProjection-structuralAttributesOf = _: 1;
    mkProjectionFindings-childBearing = _: 1;
    mkProjectionFindings-isNode = _: 1;
    mkProjectionFindings-structuralAttributesOf = _: 1;
    labeledFrom = _: 1;
    fromRegistry-parent = _: _: { };
  };
  shapes = {
    ancestorsOf-scalar = surfaces.ancestorsOf (_: 1);
    foldPreorder-key-scalar = surfaces.foldPreorder-key (_: 1);
    foldPreorder-expand-no-acc = surfaces.foldPreorder-expand (_: _: { children = [ ]; });
    foldPreorder-expand-children = surfaces.foldPreorder-expand (
      acc: _: {
        inherit acc;
        children = 1;
      }
    );
    fixpoint-step-entry = surfaces.fixpoint-step (_: {
      a = 1;
    });
    fixpoint-step-empty-seed = G.fixpoint {
      seed = { };
      step = _: 1;
    };
    seededFixpoint-entry = surfaces.seededFixpoint (_: _: { a = 1; });
    # a site applied twice is reached at its second application too: a first result that is lawful
    reachableVia-operator = surfaces.reachableVia (id: if id == "a" then [ { key = "b"; } ] else 1);
    dependentsFrontier-operator = surfaces.dependentsFrontier (id: if id == "c" then true else 1);
    # an empty frontier converges at once, so the only application is the support check's
    seededFixpoint-support = G.seededFixpoint {
      seed = E;
      frontier = { };
      step = _: _: 1;
    };
    mkEndpointProjection-child-value =
      projection G.mkEndpointProjection
        {
          childBearing = n: n == "kids";
        }
        (_: {
          kids = 1;
        });
    # `succ`'s elements are its own contract, `{ key; }`, at both of `genericClosure`'s applications
    reachableVia-element-int = surfaces.reachableVia (_: [ 1 ]);
    reachableVia-element-no-key = surfaces.reachableVia (_: [ { } ]);
    reachableVia-operator-element = surfaces.reachableVia (
      id: if id == "a" then [ { key = "b"; } ] else [ 1 ]
    );
  };

  # A binary function is applied one argument at a time, so its first application must return a
  # function: each is under-applied here, and the library's second application would abort
  binary = {
    selectEdges = surfaces.selectEdges (_: true);
    topoOrder-lessThan = surfaces.topoOrder-lessThan (_: true);
    topoOrderKahn-lessThan = surfaces.topoOrderKahn-lessThan (_: true);
    seededFixpoint = surfaces.seededFixpoint (_: { });
    seededFixpoint-support = G.seededFixpoint {
      seed = E;
      frontier = { };
      step = _: { };
    };
    foldPreorder-expand = surfaces.foldPreorder-expand (_: {
      acc = 0;
    });
    fromRegistry-parent = surfaces.fromRegistry-parent (_: null);
    fromRegistry-edges = G.reachableFrom (G.fromRegistry {
      registry = {
        a = { };
      };
      edges = _: [ ];
    }) "a";
    expandPreorder-emit = passThrough.expandPreorder-emit (_: 0);
    queryFold-combine = passThrough.queryFold-combine (_: 0);
  };

  # Functions the library applies and whose results it hands on unread: a door each, and no result
  # check. `select`'s pred forces its argument, or laziness would never apply `nodeData`.
  passThrough = {
    select-nodeData = f: G.select (g // { nodeData = f; }) (d: d == { v = "a"; });
    expandPreorder-resolve = f: (expanded { resolve = f; }).nodes;
    expandPreorder-emit = f: (expanded { emit = f; }).nodes;
    queryFold-combine = f: folded { combine = f; };
    queryFold-valueOf = f: folded { valueOf = f; };
  };
  passLawful = {
    select-nodeData = g.nodeData;
    expandPreorder-resolve = x: x;
    expandPreorder-emit = _: p: p;
    queryFold-combine = n: v: n + builtins.stringLength v;
    queryFold-valueOf = x: x;
  };
  expanded =
    over:
    G.expandPreorder (
      {
        roots = [ "a" ];
        key = x: x;
        inherit (g) edges;
      }
      // over
    );
  folded =
    over:
    G.queryFold (
      {
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
        from = "a";
        follow = G.regex.star (G.regex.lit "x");
        empty = 0;
        combine = n: v: n + builtins.stringLength v;
      }
      // over
    );
in
{
  inherit
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
}
