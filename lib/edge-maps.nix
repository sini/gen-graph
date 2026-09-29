{ prelude }:
let
  inherit (import ./key.nix "gen-graph")
    attrKey
    badResult
    callable
    callableAt
    renderId
    edgesAccessor
    keyedAttrs
    notEdgeList
    ;
  # `who` is `within <door> "materialize"` when another door reaches it (R6, `key.nix`).
  materializeAs =
    who:
    { edges, nodes, ... }:
    let
      e = edgesAccessor who edges;
    in
    keyedAttrs who nodes (
      id:
      prelude.unique (
        let
          es = e id;
        in
        if builtins.isList es then es else throw (notEdgeList who id es)
      )
    );
  inherit (prelude) door;
  # An accessor record is R5's data record: open, its missing fields refused by name at the door's
  # application (P2 rule 3).
  accessorDoor =
    name: required:
    door {
      name = "gen-graph.${name}";
      inherit required;
      open = true;
    };
  materialize = accessorDoor "materialize" [
    "edges"
    "nodes"
  ] (materializeAs "materialize");

  materializeParents = accessorDoor "materializeParents" [ "nodes" "parent" ] (
    { parent, nodes, ... }:
    let
      pa = callableAt "materializeParents" "parent" "a node id or null" parent;
      toKey = attrKey "materializeParents";
    in
    prelude.listToAttrs (
      builtins.filter (e: e.value != null) (
        map (id: {
          name = toKey id;
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
    )
  );

  # Convert target list to attrset for O(1) membership
  _targetSet =
    who: targets:
    let
      toKey = attrKey who;
    in
    builtins.listToAttrs (
      map (t: {
        name = toKey t;
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
    let
      toKey = attrKey "intersectEdges";
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet "intersectEdges" (b.${from} or [ ]);
        in
        builtins.filter (to: bSet ? ${toKey to}) aTargets
      ) (prelude.filterAttrs (from: _: b ? ${from}) a)
    );

  # `who` is `within <door> "differenceEdges"` when another door reaches it (R6, `key.nix`).
  differenceEdgesAs =
    who: a: b:
    let
      toKey = attrKey who;
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet who (b.${from} or [ ]);
        in
        builtins.filter (to: !(bSet ? ${toKey to})) aTargets
      ) a
    );
  # Set difference is not commutative, so its two edge maps are ONE record whose field names carry
  # what the argument order did (P2, R7 (b)): `differenceEdges { minuend; subtrahend; }` is the
  # minuend's edges less the subtrahend's.
  differenceEdges = door {
    name = "gen-graph.differenceEdges";
    required = [
      "minuend"
      "subtrahend"
    ];
    open = true;
  } (r: differenceEdgesAs "differenceEdges" r.minuend r.subtrahend);

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
  # R6: not published — `lib/default.nix` strips it from the surface.
  threaded = {
    materialize = materializeAs;
    differenceEdges = differenceEdgesAs;
  };
}
