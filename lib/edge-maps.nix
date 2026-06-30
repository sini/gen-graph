{ prelude }:
let
  materialize = { edges, nodes, ... }: prelude.genAttrs nodes (id: prelude.unique (edges id));

  materializeParents =
    { parent, nodes, ... }:
    prelude.listToAttrs (
      builtins.filter (e: e.value != null) (
        map (id: {
          name = id;
          value = parent id;
        }) nodes
      )
    );

  # Convert target list to attrset for O(1) membership
  _targetSet =
    targets:
    builtins.listToAttrs (
      map (t: {
        name = t;
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
    prelude.genAttrs allKeys (k: prelude.unique ((a.${k} or [ ]) ++ (b.${k} or [ ])));

  intersectEdges =
    a: b:
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet (b.${from} or [ ]);
        in
        builtins.filter (to: bSet ? ${to}) aTargets
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
        builtins.filter (to: !(bSet ? ${to})) aTargets
      ) a
    );

  selectEdges =
    pred: edgeMap:
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (from: targets: builtins.filter (to: pred from to) targets) edgeMap
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
