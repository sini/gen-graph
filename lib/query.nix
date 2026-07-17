# Labeled graph queries: reachability over labeled edges constrained by a
# label regex (Néron et al. 2015 scope-graph resolution, generalized to
# arbitrary edge labels). The engine steps a Brzozowski derivative alongside
# the graph walk; the seen-set keys on (node, canonical-derivative) pairs, so
# cyclic graphs terminate because ACI-normalized derivative sets are finite
# (Owens, Reppy & Turon 2009). `all` mode is genericClosure-backed (C-level,
# no path materialization); witness-carrying modes live beside it.
{ prelude }:
let
  regex = import ./regex.nix { inherit prelude; };

  # adapter: one plain accessor per label → the labeled contract
  labeledFrom = perLabel: {
    labeledEdges =
      id:
      builtins.concatMap (label: map (target: { inherit label target; }) (perLabel.${label} id)) (
        builtins.attrNames perLabel
      );
  };

  # `all` mode: the (node × derivative-state) product automaton, closed via
  # genericClosure. A node answers when its state is nullable.
  queryAll =
    {
      graph,
      from,
      follow,
      where ? (_: true),
    }:
    let
      st0 = follow;
      # composite seen-key: JSON of the pair — collision-free by construction for ANY
      # node id / label content (no separator-character caveat to police)
      keyOf =
        node: st:
        builtins.toJSON [
          node
          (regex.stateKey st)
        ];
      closure = builtins.genericClosure {
        startSet = [
          {
            key = keyOf from st0;
            node = from;
            st = st0;
          }
        ];
        operator =
          item:
          builtins.concatMap (
            e:
            let
              st' = regex.deriv e.label item.st;
              k = regex.stateKey st';
            in
            if k == "0" then
              [ ]
            else
              [
                {
                  key = builtins.toJSON [
                    e.target
                    k
                  ];
                  node = e.target;
                  st = st';
                }
              ]
          ) (graph.labeledEdges item.node);
      };
      # answers are a SET of node ids: listToAttrs is first-wins on duplicate
      # names, so distinct derivative states reaching the same node collapse to
      # one entry, and attrNames stays sorted.
      answers = builtins.listToAttrs (
        map (item: {
          name = item.node;
          value = true;
        }) (builtins.filter (item: regex.nullable item.st && where item.node) closure)
      );
    in
    builtins.attrNames answers;

  # `paths` mode: witness-carrying DFS. Enumerates ACYCLIC paths only (the
  # pathsBetween precedent) with derivative pruning; enumeration-priced —
  # use `all` for scale, `paths` when the witness itself is the product
  # (resolution traces, shadowing explanations).
  queryPaths =
    {
      graph,
      from,
      follow,
      where ? (_: true),
    }:
    let
      go =
        visited: pathAcc: node: st:
        let
          here =
            if regex.nullable st && where node then
              [
                {
                  inherit node;
                  path = pathAcc;
                }
              ]
            else
              [ ];
          steps = builtins.concatMap (
            e:
            let
              st' = regex.deriv e.label st;
            in
            if regex.stateKey st' == "0" || visited ? ${e.target} then
              [ ]
            else
              go (visited // { ${e.target} = true; }) (
                # witness step built in its final shape — no post-hoc strip
                pathAcc
                ++ [
                  {
                    inherit (e) label;
                    from = node;
                    to = e.target;
                  }
                ]
              ) e.target st'
          ) (graph.labeledEdges node);
        in
        here ++ steps;
    in
    go { ${from} = true; } [ ] from follow;

  query =
    args@{
      mode ? "all",
      ...
    }:
    if mode == "all" then
      queryAll (builtins.removeAttrs args [ "mode" ])
    else if mode == "paths" then
      queryPaths (builtins.removeAttrs args [ "mode" ])
    else
      throw "gen-graph.query: unknown mode '${mode}'";
in
{
  inherit labeledFrom query;
}
