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
            in
            if regex.stateKey st' == "0" then
              [ ]
            else
              [
                {
                  key = keyOf e.target st';
                  node = e.target;
                  st = st';
                }
              ]
          ) (graph.labeledEdges item.node);
      };
      answers = builtins.foldl' (
        acc: item:
        if regex.nullable item.st && where item.node then acc // { ${item.node} = true; } else acc
      ) { } closure;
    in
    builtins.attrNames answers;

  query =
    args@{
      mode ? "all",
      ...
    }:
    if mode == "all" then
      queryAll (builtins.removeAttrs args [ "mode" ])
    else
      throw "gen-graph.query: unknown mode '${mode}'";
in
{
  inherit labeledFrom query;
}
