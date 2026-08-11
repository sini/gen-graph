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
  global = import ./global.nix { inherit prelude; };
  partition = import ./partition.nix { inherit prelude; };

  # ── THE LABELED CONTRACT IS TOTAL ──
  # A labeled graph is `{ labeledEdges; nodes; }`, and `nodes` is a REQUIRED FORMAL of the
  # only constructor. The two halves of this library were built to two different contracts:
  # a labeled query is SEEDED — it starts `from` a node and walks — so it never needed to
  # know its own domain, while every global surface (`cycles`, `condensation`, `dependents`,
  # `transpose`, the ordering front door…) is NODE-SET-TOTAL and takes `{ edges, nodes }`.
  # An accessor's domain is not enumerable, so a node set cannot be recovered from
  # `labeledEdges` afterwards: without it the whole global half is simply unreachable from a
  # labeled graph, and the way that was reported was an arity abort deep inside a callee
  # that `tryEval` cannot catch.
  #
  # ABSENCE IS A DECISION. A default node set — `[ ]`, or the keys of `perLabel`, or the
  # targets appearing in the edges — makes the same failure SILENT: every global surface
  # would answer, and answer about a domain the caller never stated. A required formal makes
  # the omission report itself at the constructor, naming the missing argument, which is the
  # loudest thing the substrate offers.
  labeledFrom =
    {
      perLabel,
      nodes,
    }:
    {
      inherit nodes;
      labeledEdges =
        id:
        builtins.concatMap (label: map (target: { inherit label target; }) (perLabel.${label} id)) (
          builtins.attrNames perLabel
        );
    };

  # ── THE ONE PUBLISHED PROJECTION ──
  # `forgetLabels : labeledGraph → { edges; nodes; }` is the single sanctioned bridge from
  # the labeled half to the global half. Every global surface composes with a labeled graph
  # through it and only through it, which is what makes the composition one reviewable
  # definition instead of one ad-hoc `map (e: e.target)` per call site.
  #
  # Parallel edges that differ only in their label collapse: the plain accessor is the
  # library's set-of-targets contract, which `mkGraph` states the same way
  # (`lib/registry.nix`, `edges = id: prelude.unique …`). Multiplicity is a labeled-layer
  # fact, and a projection that leaked it would hand the global surfaces a number none of
  # them has a meaning for — `cycles` and `condensation` read reachability, not counts.
  forgetLabels =
    {
      labeledEdges,
      nodes,
      ...
    }:
    {
      inherit nodes;
      edges = id: prelude.unique (map (e: e.target) (labeledEdges id));
    };

  # ── WHICH EDGES SATISFYING `p` LIE ON A CYCLE ──
  # `cyclicEdgesWhere : labeledGraph → (label → bool) → [ { from; label; to; } ]`.
  # Empty ⇒ no cycle of this graph carries an edge whose label satisfies `p`.
  #
  # It completes a family rather than opening one: `cycles` answers WHICH NODES lie on a
  # cycle, `cyclePaths` answers WHICH WALK, and this answers WHICH EDGES SATISFYING p — the
  # `Where` suffix `reachableWhere` already establishes.
  #
  # THE CONSTRUCTION IS THE COMPOSITION, and it is why the labeled contract had to become
  # total: forget the labels, partition the projection into strongly connected components,
  # then JOIN BACK onto the retained labelled edge list. Two endpoints in one component are
  # mutually reachable, so the edge between them closes a cycle; an edge to itself is one
  # already. The projection ALONE cannot answer this — it has forgotten the labels — and the
  # labelled edges alone cannot either, because being on a cycle is a global property. The
  # pair answers it exactly.
  #
  # THEORY. Apt, Blair & Walker 1988, *Towards a Theory of Declarative Knowledge*, Lemma 1:
  # a program is stratified iff its dependency graph has no cycle containing a negative
  # edge; the proof of the converse decomposes the dependency graph into strongly connected
  # components (archived text at `used/markdown/apt-1988-towards-theory-declarative-
  # knowledge.md`:522-523 and :539, papers `d7c2e73`). So `condensation` is not a
  # construction that happens to agree with the result — it is the primary's own proof
  # method, and this query is that method's graph half.
  #
  # ★ THE GRAPH HALF IS ALL THIS LIBRARY CAN SEE, WHICH IS WHY THE NAME IS WHAT IT IS.
  # Lemma 1 is a BICONDITIONAL between a program property and a graph property. gen-graph
  # has no programs, no relation symbols and no clauses; and which labels count as negative
  # arrives from the caller, so the library does not even know that much. Naming this result
  # after the program-level property would have the library assert a theorem about objects
  # it cannot observe. A caller that does have programs — the den engine, at its
  # well-definedness gate — names it there, where the reading "this label MEANS negation"
  # exists.
  #
  # WITNESSES, not a boolean: a caller refusing a graph has to say which edges did it, and
  # the answer is exactly the material for that message. The order is (from, label, to)
  # ascending so the answer is a function of the graph and not of accessor enumeration.
  cyclicEdgesWhere =
    graph: p:
    let
      plain = forgetLabels graph;
      # The partition ARM by name, never the door: this consumer reads the tag map and
      # nothing else, so it has no stake in which algorithm the door defaults to.
      inherit (partition.fbNode plain) sccOf;
      hits = builtins.concatMap (
        from:
        map (e: {
          inherit from;
          inherit (e) label;
          to = e.target;
        }) (builtins.filter (e: p e.label && sccOf.${from} == sccOf.${e.target}) (graph.labeledEdges from))
      ) plain.nodes;
      less =
        a: b:
        if a.from != b.from then
          a.from < b.from
        else if a.label != b.label then
          a.label < b.label
        else
          a.to < b.to;
    in
    builtins.sort less hits;

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
  inherit
    labeledFrom
    forgetLabels
    cyclicEdgesWhere
    query
    queryFold
    ;
}
