{ lib }:
let
  roots =
    { edges, nodes, ... }:
    let
      allTargets = builtins.listToAttrs (
        lib.concatMap (
          id:
          map (t: {
            name = t;
            value = true;
          }) (edges id)
        ) nodes
      );
    in
    builtins.sort builtins.lessThan (builtins.filter (id: !(allTargets ? ${id})) nodes);

  leaves =
    { edges, nodes, ... }:
    builtins.sort builtins.lessThan (builtins.filter (id: edges id == [ ]) nodes);

  select = { nodes, nodeData, ... }: pred: builtins.filter (id: pred (nodeData id)) nodes;
in
{
  inherit roots leaves select;
}
