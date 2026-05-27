{ lib }:
let
  materialize = { edges, nodes, ... }: lib.genAttrs nodes (id: lib.unique (edges id));

  materializeParents =
    { parent, nodes, ... }:
    lib.listToAttrs (
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
    lib.genAttrs allKeys (k: lib.unique ((a.${k} or [ ]) ++ (b.${k} or [ ])));

  intersectEdges =
    a: b:
    lib.filterAttrs (_: targets: targets != [ ]) (
      lib.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet (b.${from} or [ ]);
        in
        builtins.filter (to: bSet ? ${to}) aTargets
      ) (lib.filterAttrs (from: _: b ? ${from}) a)
    );

  differenceEdges =
    a: b:
    lib.filterAttrs (_: targets: targets != [ ]) (
      lib.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet (b.${from} or [ ]);
        in
        builtins.filter (to: !(bSet ? ${to})) aTargets
      ) a
    );

  selectEdges =
    pred: edgeMap:
    lib.filterAttrs (_: targets: targets != [ ]) (
      lib.mapAttrs (from: targets: builtins.filter (to: pred from to) targets) edgeMap
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
