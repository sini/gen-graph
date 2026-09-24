{ prelude }:
let
  inherit (import ./key.nix)
    attrKey
    badResult
    callableAt
    edgesAccessor
    notEdgeList
    renderId
    ;
  roots =
    { edges, nodes, ... }:
    let
      e = edgesAccessor "roots" edges;
      allTargets = builtins.listToAttrs (
        prelude.concatMap (
          id:
          map
            (t: {
              name = attrKey t;
              value = true;
            })
            (
              let
                es = e id;
              in
              if builtins.isList es then es else throw (notEdgeList "roots" id es)
            )
        ) nodes
      );
    in
    builtins.sort builtins.lessThan (builtins.filter (id: !(allTargets ? ${attrKey id})) nodes);

  leaves =
    { edges, nodes, ... }:
    let
      e = edgesAccessor "leaves" edges;
    in
    builtins.sort builtins.lessThan (
      builtins.filter (
        id:
        let
          es = e id;
        in
        if builtins.isList es then es == [ ] else throw (notEdgeList "leaves" id es)
      ) nodes
    );

  select =
    { nodes, nodeData, ... }:
    pred:
    let
      p = callableAt "select" "pred" "a bool" pred;
      # applied, never read: its result is handed to `pred`
      nd = callableAt "select" "nodeData" "a node's data" nodeData;
    in
    builtins.filter (
      id:
      let
        b = p (nd id);
      in
      if builtins.isBool b then b else badResult "select" "pred" "on the node ${renderId id}" "a bool" b
    ) nodes;
in
{
  inherit roots leaves select;
}
