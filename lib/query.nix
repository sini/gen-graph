# Labeled graph queries: reachability over labeled edges constrained by a
# label regex (Néron et al. 2015 scope-graph resolution, generalized to
# arbitrary edge labels). The engine steps a Brzozowski derivative alongside
# the graph walk; the seen-set keys on (node, canonical-derivative) pairs, so
# cyclic graphs terminate: a regular expression has only finitely many
# derivatives modulo the ACI identities of alternation — Brzozowski 1964
# Thm 5.2, over the similarity of his Def 5.2 — and `lib/regex.nix` PERFORMS
# that normalization, which the theorem requires done rather than merely true.
# (Owens, Reppy & Turon 2009 supply the enlarged rule set that file also runs;
# the finiteness result is Brzozowski's and ORT cite it as his.) That is the
# `all` engine; witness modes terminate by acyclic path enumeration instead.
# `all` mode is genericClosure-backed (C-level, no path materialization);
# witness-carrying modes live beside it.
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

  # ── THE LABELED TRANSPOSE ──
  # `labeledTranspose : labeledGraph → labeledGraph`. Every edge is reversed AND CARRIES
  # ITS LABEL, so the reverse read of a labeled query is the forward construction over the
  # transposed accessor with the query's parameters untouched — one construction with a
  # direction argument, rather than two constructions that can drift apart.
  #
  # THEORY. Mokhov 2017 §5.2 *Graph Transpose*: transpose flips the arguments of `connect`
  # and leaves `overlay` unchanged, so direction is REVERSED, not erased — the same law
  # `global.nix`'s `transpose` realises on the plain accessor. The labelled reading adds
  # nothing to that law and takes nothing away: a label is carried BY an edge, so flipping
  # the edge relation moves the label with it, and the law's own prohibition is on erasure.
  # Projecting a labeled graph through `forgetLabels` to reach the plain `transpose` erases
  # precisely the component the query engine reads, which is why that composition is not a
  # labeled transpose and this is not sugar for it.
  #
  # WHY IT IS A FUNCTION AT ALL. An accessor's domain is not enumerable, and reversal is a
  # question about who points AT a node — unanswerable without visiting every source. The
  # total labeled contract above, where `nodes` is a required formal, is what supplies that
  # domain; against the seeded-only half of the contract there was nothing to write.
  #
  # COST AND SHARING. Θ(n + E): one pass of the accessor over `nodes`, one `groupBy`, no
  # repeated `//`. The index is a single thunk shared by every lookup, so the source
  # accessor is read once for the whole transposed graph rather than once per queried node
  # — and not at all if the result is never queried.
  #
  # EDGE ORDER is source order: a node's in-edges arrive in `nodes` order, then in that
  # source's own edge order. So the transpose is a function of the graph and not of when it
  # was asked, and `labeledTranspose (labeledTranspose g)` restores `g`'s edge relation
  # with each node's out-edges re-sorted into `nodes` order.
  labeledTranspose =
    {
      labeledEdges,
      nodes,
      ...
    }:
    let
      incoming = builtins.groupBy (e: e.target) (
        builtins.concatMap (
          from:
          map (e: {
            inherit (e) label target;
            inherit from;
          }) (labeledEdges from)
        ) nodes
      );
    in
    {
      inherit nodes;
      labeledEdges =
        id:
        map (e: {
          inherit (e) label;
          target = e.from;
        }) (incoming.${id} or [ ]);
    };

  # ── THE BOUNDARY MARKS, AND THE DIAGNOSTIC THAT MAKES THEM VISIBLE ──
  # `boundedBy : labeledGraph → (nodeId → [ mark ]) → boundedLabeledGraph`, where a mark is
  # `{ name; admits; }` — a NAME the diagnostic can quote and a `label → bool` predicate.
  # The result is a labeled graph whose `labeledEdges` yields only admitted edges, plus a
  # companion `withheld : nodeId → [ { label; target; marks; } ]` in which `marks` is every
  # mark that withheld that edge, never empty.
  #
  # NARROWING IS STRUCTURAL, NOT PROMISED. The construction only ever REMOVES edges from
  # what the underlying accessor offers, so a caller holding the bounded graph has no
  # operation that recovers a withheld edge into the walk: widening is not forbidden, it is
  # unsayable. That is the whole reason the marks are applied at the accessor rather than
  # inside the label regex — `regex.deriv` takes a label and an expression and never sees a
  # node, so a per-node intersection is not expressible there at all.
  #
  # SILENCE IS NEVER A RESULT, which is why `withheld` is not optional. An accessor that
  # filtered and said nothing would answer an empty query with an empty answer and no way
  # to tell a boundary from an absent edge — the two are indistinguishable in the answer
  # and must not be indistinguishable in the diagnostic. A caller whose query came back
  # short asks `withheld` at the node and is told which mark did it, by name.
  #
  # AN EDGE WITHHELD BY SEVERAL MARKS IS ONE DIAGNOSTIC ENTRY NAMING ALL OF THEM. Picking
  # one would make the report depend on mark order, and reporting the edge once per mark
  # would make `withheld` uncountable as a set of edges.
  #
  # LAZINESS is preserved node-wise: the per-node verdict is memoized as a thunk so the two
  # accessors share one classification, and no node's edges are forced until it is asked
  # for. Only the memo's spine — one name per member of `nodes` — is built eagerly.
  boundedBy =
    graph: marksOf:
    let
      classify =
        id:
        let
          marks = marksOf id;
          verdicts = map (e: {
            edge = {
              inherit (e) label target;
            };
            blockers = builtins.filter (m: !(m.admits e.label)) marks;
          }) (graph.labeledEdges id);
        in
        {
          admitted = map (v: v.edge) (builtins.filter (v: v.blockers == [ ]) verdicts);
          withheld = map (
            v:
            v.edge
            // {
              marks = map (m: m.name) v.blockers;
            }
          ) (builtins.filter (v: v.blockers != [ ]) verdicts);
        };
      memo = builtins.listToAttrs (
        map (id: {
          name = id;
          value = classify id;
        }) graph.nodes
      );
      at = id: memo.${id} or (classify id);
    in
    {
      inherit (graph) nodes;
      labeledEdges = id: (at id).admitted;
      withheld = id: (at id).withheld;
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

  # ── THE ARRIVAL CARRIER: EDGE-KEYED, LINEAR, DISTANCE-CARRYING ──
  # `queryArrivals` walks the same (node × derivative-state) product automaton `queryAll`
  # closes, and differs from it in exactly two respects, both of which are the point:
  #
  #   1. IT IS KEYED ON THE ARRIVING EDGE, not on the node. `queryAll`'s key is
  #      ⟨node, derivative-state⟩, so two DISTINCT labels reaching one node collapse to one
  #      answer whenever the follow expression derivates both to the same state — an
  #      alternation over the two labels does exactly that. The collapse is invisible in the
  #      answer: nothing in `[ "x" ]` says a second edge was dropped. Keying on
  #      ⟨arriving edge, derivative-state⟩ keeps both arrivals distinct, and termination is
  #      untouched: edges are finite and Brzozowski derivatives are finite modulo the ACI
  #      identities `regex.nix` normalizes by, so the refined key set is still finite and
  #      still fences cycles. Refining a fence does not remove it. The price is the
  #      in-degree factor — the key space is |E| × |derivatives| where `queryAll`'s is
  #      |V| × |derivatives| — which is why `queryAll` keeps its own contract and this is a
  #      separate surface rather than a replacement.
  #
  #   2. IT RETURNS A SEQUENCE, NOT A SET. Answers come out in the closure's own visitation
  #      order with no `listToAttrs`/`attrNames` round trip, so neither a reorder nor a
  #      node-level dedup happens after the walk. A caller wanting the coarser answer states
  #      the collapse it wants; it cannot recover multiplicity the carrier already threw away.
  #
  # `advance` IS A REQUIRED FORMAL AND CARRIES THE DISTANCE RULE.
  # `advance : { distance; from; label; to; } → int` is handed the distance already
  # accumulated AT the step's source together with the step, and returns the distance after
  # it. Plain hop count is `s: s.distance + 1`. A caller whose graph reifies a relation as a
  # node with labelled incidence — where one relation is spelled as two edges through the
  # reified node — writes a rule that does not increment on the edge completing the pair, so
  # that a representation choice does not silently move a distance. There is no default:
  # a defaulted distance rule is a semantics nobody wrote down, and this library already
  # takes the required-formal position on `nodes` for the same reason.
  #
  # ★ WHAT `distance` IS, STATED AS THE BOUND IT IS, BECAUSE THE BOUND IS SHARP.
  # The payload is the distance of the FIRST arrival at a key in visitation order —
  # `genericClosure` keeps the first item inserted under a key and discards later ones, so
  # no minimum is computed anywhere.
  #
  # That first arrival IS the minimum when `advance` is nondecreasing in hop count: the
  # visitation order is nondecreasing in hops (`ci/tests/closure-order.nix` asserts exactly
  # that property), so under such a rule the first arrival is also the cheapest. Plain hop
  # count and every rule charging a positive constant are of that kind.
  #
  # IT IS NOT THE MINIMUM FOR A RULE THAT CAN CHARGE ZERO, and the failure is not merely
  # that the payload is wrong — the cheaper number can be ABSENT FROM THE ANSWER ALTOGETHER.
  # A route that is longer in hops but charges zero on some of them can total less than a
  # shorter one, and the shorter one is visited first. Whether the cheaper arrival survives
  # depends on its LAST edge: arrivals are distinguished by the edge that delivered them, so
  # a cheaper route entering by a different final edge is kept beside the dearer one and a
  # caller can fold the minimum out of the sequence — but a cheaper route entering by the
  # SAME final edge in the same derivative state shares the key with the dearer first
  # arrival and is discarded, and then no fold of this sequence recovers it. Both halves are
  # measured in `ci/tests/arrivals.nix`, against a hop-count control in the same run.
  # A caller needing a true minimum under a zero-charging rule needs a relaxing traversal,
  # which this is not and does not pretend to be.
  #
  # `via` is `null` at the root and `{ from; label; }` at every other arrival — the root
  # arrived by no edge, and saying so is a statement rather than a missing field.
  # `admission` is the canonical key of the residual follow expression at the arrival: the
  # admission policy that remains in force there, and the component a caller needs to state
  # a ⟨node, derivative-state⟩ collapse of its own.
  queryArrivals =
    {
      graph,
      from,
      follow,
      advance,
      where ? (_: true),
    }:
    let
      closure = builtins.genericClosure {
        startSet = [
          {
            key = builtins.toJSON [
              null
              from
              (regex.stateKey follow)
            ];
            node = from;
            st = follow;
            distance = 0;
            via = null;
          }
        ];
        operator =
          item:
          builtins.concatMap (
            e:
            let
              st' = regex.deriv e.label item.st;
              k = regex.stateKey st';
              via = {
                from = item.node;
                inherit (e) label;
              };
            in
            if k == "0" then
              [ ]
            else
              [
                {
                  key = builtins.toJSON [
                    via
                    e.target
                    k
                  ];
                  node = e.target;
                  st = st';
                  distance = advance {
                    inherit (item) distance;
                    from = item.node;
                    inherit (e) label;
                    to = e.target;
                  };
                  inherit via;
                }
              ]
          ) (graph.labeledEdges item.node);
      };
    in
    map (item: {
      inherit (item) node distance via;
      admission = regex.stateKey item.st;
    }) (builtins.filter (item: regex.nullable item.st && where item.node) closure);

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
    labeledTranspose
    boundedBy
    cyclicEdgesWhere
    query
    queryArrivals
    queryFold
    ;
}
