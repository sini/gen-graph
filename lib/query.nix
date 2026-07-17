# Labeled graph queries: reachability over labeled edges constrained by a
# label regex (Néron et al. 2015 scope-graph resolution, generalized to
# arbitrary edge labels). The engine steps a Brzozowski derivative alongside
# the graph walk; the seen-set keys on (node, canonical-derivative) pairs, so
# cyclic graphs terminate because ACI-normalized derivative sets are finite
# (Owens, Reppy & Turon 2009) — that is the `all` engine; witness modes
# terminate by acyclic path enumeration instead. `all` mode is
# genericClosure-backed (C-level, no path materialization); witness-carrying
# modes live beside it.
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

  # ── per-query label order (Néron et al. specificity; van Antwerpen et al.
  # per-query ≤ with an end-of-path token): compare witness paths
  # lexicographically on label ranks; when one word is exhausted, its
  # end-of-path rank competes against the other word's next label rank —
  # the default endOfPath = -1 makes stopping outrank everything (a proper
  # prefix beats its extensions); a higher endOfPath lets continuation on
  # lower-ranked labels beat stopping. ──
  ranksOf =
    order:
    (builtins.foldl'
      (acc: l: {
        i = acc.i + 1;
        m = acc.m // {
          ${l} = acc.i;
        };
      })
      {
        i = 0;
        m = { };
      }
      (order.labels or [ ])
    ).m;

  rankOf = order: label: (ranksOf order).${label} or (builtins.length (order.labels or [ ]));

  rankWordOf = order: path: map (p: rankOf order p.label) path;

  # strict word comparison with the end-of-path rank at exhaustion
  wordLess =
    eop: wa: wb:
    let
      la = builtins.length wa;
      lb = builtins.length wb;
      go =
        i:
        if i >= la && i >= lb then
          false # equal words
        else if i >= la then
          eop < builtins.elemAt wb i # a stopped; a wins iff stopping outranks b's continuation
        else if i >= lb then
          builtins.elemAt wa i < eop # b stopped; a wins iff its continuation outranks stopping
        else if builtins.elemAt wa i < builtins.elemAt wb i then
          true
        else if builtins.elemAt wa i > builtins.elemAt wb i then
          false
        else
          go (i + 1);
    in
    go 0;

  pathLess =
    order: pa: pb:
    wordLess (order.endOfPath or (-1)) (rankWordOf order pa) (rankWordOf order pb);

  queryVisible =
    args@{
      order ? {
        labels = [ ];
      },
      groupBy ? (ans: ans.node),
      ...
    }:
    let
      answers = queryPaths (
        builtins.removeAttrs args [
          "order"
          "groupBy"
        ]
      );
      groups = builtins.groupBy groupBy answers;
      split =
        anss:
        let
          sorted' = builtins.sort (a: b: pathLess order a.path b.path) anss;
          best = builtins.head sorted';
          isMin = a: !(pathLess order best.path a.path);
        in
        {
          visible = builtins.filter isMin sorted';
          shadowed = builtins.filter (a: pathLess order best.path a.path) sorted';
        };
      parts = builtins.mapAttrs (_: split) groups;
      names = builtins.sort builtins.lessThan (builtins.attrNames parts);
    in
    {
      visible = builtins.concatMap (k: parts.${k}.visible) names;
      shadowed = builtins.concatMap (k: parts.${k}.shadowed) names;
    };

  queryLayers =
    args@{
      order ? {
        labels = [ ];
      },
      ...
    }:
    let
      answers = queryPaths (builtins.removeAttrs args [ "order" ]);
      # layer key = the rank word as JSON (parses back losslessly; no digit-string fragility)
      keyed = builtins.groupBy (ans: builtins.toJSON (rankWordOf order ans.path)) answers;
      words = builtins.attrNames keyed;
      less = ka: kb: wordLess (order.endOfPath or (-1)) (builtins.fromJSON ka) (builtins.fromJSON kb);
    in
    map (k: keyed.${k}) (builtins.sort less words);

  # Fold a combining operation over a query's answer set, in canonical
  # (sorted-node) order. The caller's (empty, combine) is expected to be a
  # commutative-idempotent monoid — under those laws the canonical order is
  # unobservable (Arntzenius & Krishnaswami's Datafun restricts fixpoints to
  # bounded join-semilattices for exactly this reason). Recursive node-valued
  # fixpoints (a node's value depending on neighbors' values) are fixpoint.nix
  # territory, not this fold.
  queryFold =
    args@{
      empty,
      combine,
      valueOf ? (id: id),
      ...
    }:
    builtins.foldl' (acc: id: combine acc (valueOf id)) empty (
      queryAll (
        builtins.removeAttrs args [
          "empty"
          "combine"
          "valueOf"
          "mode" # `query { mode = "fixpoint"; … }` dispatches here — strip the alias
        ]
      )
    );

  # ── THE complete mode dispatch (final form) ────────────────────────────────
  query =
    args@{
      mode ? "all",
      ...
    }:
    let
      core = builtins.removeAttrs args [
        "mode"
        "order"
        "groupBy"
      ];
    in
    if mode == "all" then
      queryAll core
    else if mode == "paths" then
      queryPaths core
    else if mode == "visible" then
      queryVisible (builtins.removeAttrs args [ "mode" ])
    else if mode == "layers" then
      queryLayers (builtins.removeAttrs args [ "mode" ])
    else if mode == "fixpoint" then
      # fixpoint consumption IS the ACI fold — the mode string dispatches to it;
      # lawfulness (commutative-idempotent combine) is the caller's contract
      queryFold (builtins.removeAttrs args [ "mode" ])
    else
      throw "gen-graph.query: unknown mode '${mode}'";
in
{
  inherit labeledFrom query queryFold;
}
