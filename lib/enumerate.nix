{ prelude }:
let
  inherit (import ./key.nix) attrKey;
  roots =
    { edges, nodes, ... }:
    let
      allTargets = builtins.listToAttrs (
        prelude.concatMap (
          id:
          map (t: {
            name = attrKey t;
            value = true;
          }) (edges id)
        ) nodes
      );
    in
    builtins.sort builtins.lessThan (builtins.filter (id: !(allTargets ? ${attrKey id})) nodes);

  leaves =
    { edges, nodes, ... }:
    builtins.sort builtins.lessThan (builtins.filter (id: edges id == [ ]) nodes);

  select = { nodes, nodeData, ... }: pred: builtins.filter (id: pred (nodeData id)) nodes;
in
{
  inherit roots leaves select;
}
