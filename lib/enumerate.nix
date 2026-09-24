{ prelude }:
let
  inherit (import ./key.nix) attrKey edgesAccessor notEdgeList;
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

  select = { nodes, nodeData, ... }: pred: builtins.filter (id: pred (nodeData id)) nodes;
in
{
  inherit roots leaves select;
}
