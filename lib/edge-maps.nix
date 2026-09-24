{ prelude }:
let
  inherit (import ./key.nix)
    attrKey
    badResult
    callable
    callableAt
    renderId
    edgesAccessor
    keyedAttrs
    notEdgeList
    ;
  materialize =
    { edges, nodes, ... }:
    let
      e = edgesAccessor "materialize" edges;
    in
    keyedAttrs nodes (
      id:
      prelude.unique (
        let
          es = e id;
        in
        if builtins.isList es then es else throw (notEdgeList "materialize" id es)
      )
    );

  materializeParents =
    { parent, nodes, ... }:
    let
      pa = callableAt "materializeParents" "parent" "a node id or null" parent;
    in
    prelude.listToAttrs (
      builtins.filter (e: e.value != null) (
        map (id: {
          name = attrKey id;
          value =
            let
              p = pa id;
            in
            if builtins.isAttrs p || builtins.isList p || builtins.isFunction p then
              badResult "materializeParents" "parent" (renderId id) "a node id or null" p
            else
              p;
        }) nodes
      )
    );

  # Convert target list to attrset for O(1) membership
  _targetSet =
    targets:
    builtins.listToAttrs (
      map (t: {
        name = attrKey t;
        value = true;
      }) targets
    );

  unionEdges =
    a: b:
    let
      aKeys = builtins.attrNames a;
      bKeys = builtins.filter (k: !(a ? ${k})) (builtins.attrNames b);
      allKeys = aKeys ++ bKeys;
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.genAttrs allKeys (k: prelude.unique ((a.${k} or [ ]) ++ (b.${k} or [ ])))
    );

  intersectEdges =
    a: b:
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet (b.${from} or [ ]);
        in
        builtins.filter (to: bSet ? ${attrKey to}) aTargets
      ) (prelude.filterAttrs (from: _: b ? ${from}) a)
    );

  differenceEdges =
    a: b:
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet (b.${from} or [ ]);
        in
        builtins.filter (to: !(bSet ? ${attrKey to})) aTargets
      ) a
    );

  selectEdges =
    pred: edgeMap:
    let
      p = callableAt "selectEdges" "pred" "a bool" pred;
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: targets:
        builtins.filter (
          to:
          let
            h = p from;
            b = h to;
          in
          if !(builtins.isFunction h || callable h) then
            badResult "selectEdges" "pred" "on the source ${renderId from}" "a function from a target to a bool"
              h
          else if builtins.isBool b then
            b
          else
            badResult "selectEdges" "pred" "on the edge ${renderId from} -> ${renderId to}" "a bool" b
        ) targets
      ) edgeMap
    );
in
{
  inherit
    materialize
    materializeParents
    unionEdges
    intersectEdges
    differenceEdges
    selectEdges
    ;
}
