{ prelude }:
let
  inherit (import ./key.nix "gen-graph")
    attrKey
    badResult
    callableAt
    edgesAccessor
    notEdgeList
    renderId
    ;
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
  roots = accessorDoor "roots" [ "edges" "nodes" ] (
    { edges, nodes, ... }:
    let
      e = edgesAccessor "roots" edges;
      toKey = attrKey "roots";
      allTargets = builtins.listToAttrs (
        prelude.concatMap (
          id:
          map
            (t: {
              name = toKey t;
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
    builtins.sort builtins.lessThan (builtins.filter (id: !(allTargets ? ${toKey id})) nodes)
  );

  leaves = accessorDoor "leaves" [ "edges" "nodes" ] (
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
    )
  );

  select = accessorDoor "select" [ "nodes" "nodeData" ] (
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
    ) nodes
  );
in
{
  inherit roots leaves select;
}
