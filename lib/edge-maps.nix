{ prelude }:
let
  inherit (import ./key.nix "gen-graph")
    attrKey
    badResult
    callable
    callableAt
    renderId
    edgesAccessor
    keyedAttrs
    notEdgeList
    ;
  # `who` is `within <door> "materialize"` when another door reaches it (R6, `key.nix`).
  materializeAs =
    who:
    { edges, nodes, ... }:
    let
      e = edgesAccessor who edges;
    in
    keyedAttrs who nodes (
      id:
      prelude.unique (
        let
          es = e id;
        in
        if builtins.isList es then es else throw (notEdgeList who id es)
      )
    );
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
  materialize = accessorDoor "materialize" [
    "edges"
    "nodes"
  ] (materializeAs "materialize");

  materializeParents = accessorDoor "materializeParents" [ "nodes" "parent" ] (
    { parent, nodes, ... }:
    let
      pa = callableAt "materializeParents" "parent" "a node id or null" parent;
      toKey = attrKey "materializeParents";
    in
    prelude.listToAttrs (
      builtins.filter (e: e.value != null) (
        map (id: {
          name = toKey id;
          value =
            let
              p = pa id;
            in
            if builtins.isAttrs p || builtins.isList p || builtins.isFunction p then
              badResult "materializeParents" "parent" (renderId id) "a node id or null" p
            else
              p;
        }) nodes
      )
    )
  );

  # Convert target list to attrset for O(1) membership
  _targetSet =
    who: targets:
    let
      toKey = attrKey who;
    in
    builtins.listToAttrs (
      map (t: {
        name = toKey t;
        value = true;
      }) targets
    );

  unionEdges =
    a: b:
    let
      aKeys = builtins.attrNames a;
      bKeys = builtins.filter (k: !(a ? ${k})) (builtins.attrNames b);
      allKeys = aKeys ++ bKeys;
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.genAttrs allKeys (k: prelude.unique ((a.${k} or [ ]) ++ (b.${k} or [ ])))
    );

  intersectEdges =
    a: b:
    let
      toKey = attrKey "intersectEdges";
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet "intersectEdges" (b.${from} or [ ]);
        in
        builtins.filter (to: bSet ? ${toKey to}) aTargets
      ) (prelude.filterAttrs (from: _: b ? ${from}) a)
    );

  # `who` is `within <door> "differenceEdges"` when another door reaches it (R6, `key.nix`).
  differenceEdgesAs =
    who: a: b:
    let
      toKey = attrKey who;
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: aTargets:
        let
          bSet = _targetSet who (b.${from} or [ ]);
        in
        builtins.filter (to: !(bSet ? ${toKey to})) aTargets
      ) a
    );
  # Set difference is not commutative, so its two edge maps are ONE record whose field names carry
  # what the argument order did (P2, R7 (b)): `differenceEdges { minuend; subtrahend; }` is the
  # minuend's edges less the subtrahend's.
  differenceEdges = door {
    name = "gen-graph.differenceEdges";
    required = [
      "minuend"
      "subtrahend"
    ];
    open = true;
  } (r: differenceEdgesAs "differenceEdges" r.minuend r.subtrahend);

  selectEdges =
    pred: edgeMap:
    let
      p = callableAt "selectEdges" "pred" "a bool" pred;
    in
    prelude.filterAttrs (_: targets: targets != [ ]) (
      prelude.mapAttrs (
        from: targets:
        builtins.filter (
          to:
          let
            h = p from;
            b = h to;
          in
          if !(builtins.isFunction h || callable h) then
            badResult "selectEdges" "pred" "on the source ${renderId from}" "a function from a target to a bool"
              h
          else if builtins.isBool b then
            b
          else
            badResult "selectEdges" "pred" "on the edge ${renderId from} -> ${renderId to}" "a bool" b
        ) targets
      ) edgeMap
    );

  # ── THE LABELED RECORD ──
  # A labeled graph is `{ labeledEdges; nodes; }`, `labeledEdges : id → [ { label; target; } ]`,
  # built by hand as data. It is not resolvable here: resolution is gen-scope's `resolve`, over an
  # evaluated scope (ADR-0008). What this library keeps of it is classical — the projection to the
  # plain accessor, the transpose, and `cyclicEdgesWhere` (`partition.nix`) — and every one of those
  # is NODE-SET-TOTAL, which is why `nodes` is required: an accessor's domain is not enumerable, so a
  # node set cannot be recovered from `labeledEdges` afterwards.
  # The record is R5's data record: open, its missing fields refused by name at the door's
  # application (P2 rule 3).
  labeledDoor =
    name:
    door {
      name = "gen-graph.${name}";
      required = [
        "labeledEdges"
        "nodes"
      ];
      open = true;
    };

  # ── THE ACCESSOR'S RESULT IS A CLAIM, CHECKED WHERE IT IS READ ──
  # `labeledEdges` is a caller-supplied function, so every surface that applies it receives a value
  # it did not construct. What a surface READS of that value has a type: the result is a list, an
  # element is an attrset, a label and a target are strings (a target is a node id, `key.nix`).
  # Read unguarded, a violation aborted past `tryEval` at the read, or — a non-string label never
  # equals a literal — was a silent wrong answer. So each read goes through a guard that refuses by
  # the surface's name: the accessor is read where it already was, never pre-scanned, and a field
  # is checked where it is READ, so the guard refuses exactly what the unguarded read died on or
  # misread, no earlier and no later.
  #
  # The accessor itself is the first thing read, so it is the first thing checked: a value that is
  # not callable is refused by name, where applying it aborted. What a function does with its
  # argument is not decidable here — a pattern formal `{ x }: …` is a function and still aborts on
  # a node id — so that input has a falsifier cell (`ci/tests-error.nix`) instead. The id is
  # rendered only when it is a string: a refusal that coerced a caller value into its own message
  # would abort in the act of refusing.
  edgesAt =
    surface: graph: id:
    let
      f = graph.labeledEdges or null;
      es = f id;
    in
    if !(builtins.isFunction f || callable f) then
      throw "gen-graph.${surface}: the graph's labeledEdges is ${
        if graph ? labeledEdges then "a ${builtins.typeOf f}" else "absent"
      }, not a function from a node id to a list of { label; target; }"
    else if builtins.isList es then
      es
    else
      throw "gen-graph.${surface}: labeledEdges ${renderId id} returned a ${builtins.typeOf es}, not a list of { label; target; }";

  fieldOf =
    field: what: surface: id: e:
    let
      at = "gen-graph.${surface}: labeledEdges ${renderId id} returned";
    in
    if !builtins.isAttrs e then
      throw "${at} an element of type ${builtins.typeOf e}, not an edge { label; target; }"
    else if !(e ? ${field}) then
      throw "${at} an edge with no ${field}"
    else if !builtins.isString e.${field} then
      throw "${at} an edge whose ${field} is of type ${builtins.typeOf e.${field}}; ${what}"
    else
      e.${field};
  labelOf = fieldOf "label" "a label is a letter of the query alphabet, a string";
  targetOf = fieldOf "target" "a target is a node id, a string";

  # ── THE ONE PUBLISHED PROJECTION ──
  # `forgetLabels : labeledGraph → { edges; nodes; }` is the single sanctioned bridge from the
  # labeled record to the global surfaces. Every global surface composes with a labeled record
  # through it and only through it, which is what makes the composition one reviewable definition
  # instead of one ad-hoc `map (e: e.target)` per call site.
  #
  # Parallel edges that differ only in their label collapse: the plain accessor is the library's
  # set-of-targets contract, which `mkGraph` states the same way (`lib/registry.nix`,
  # `edges = id: prelude.unique …`). Multiplicity is a labeled-layer fact, and a projection that
  # leaked it would hand the global surfaces a number none of them has a meaning for — `cycles` and
  # `condensation` read reachability, not counts.
  forgetLabels = labeledDoor "forgetLabels" forgetLabelsCore;
  forgetLabelsCore =
    graph@{
      labeledEdges,
      nodes,
      ...
    }:
    {
      inherit nodes;
      edges = id: prelude.unique (map (targetOf "forgetLabels" id) (edgesAt "forgetLabels" graph id));
    };

  # ── THE LABELED TRANSPOSE ──
  # `labeledTranspose : labeledGraph → labeledGraph`. Every edge is reversed AND CARRIES ITS LABEL.
  #
  # THEORY. Mokhov 2017 §5.2 *Graph Transpose*: transpose flips the arguments of `connect` and
  # leaves `overlay` unchanged, so direction is REVERSED, not erased — the same law `global.nix`'s
  # `transpose` realises on the plain accessor. The labelled reading adds nothing to that law and
  # takes nothing away: a label is carried BY an edge, so flipping the edge relation moves the label
  # with it, and the law's own prohibition is on erasure. Projecting through `forgetLabels` to reach
  # the plain `transpose` erases the labels, which is why that composition is not a labeled
  # transpose and this is not sugar for it.
  #
  # WHY IT IS A FUNCTION AT ALL. Reversal is a question about who points AT a node — unanswerable
  # without visiting every source. The required `nodes` is what supplies that domain.
  #
  # COST AND SHARING. Θ(n + E): one pass of the accessor over `nodes`, one `groupBy`, no repeated
  # `//`. The index is a single thunk shared by every lookup, so the source accessor is read once
  # for the whole transposed graph rather than once per queried node — and not at all if the result
  # is never read.
  #
  # EDGE ORDER is source order: a node's in-edges arrive in `nodes` order, then in that source's own
  # edge order. So the transpose is a function of the graph and not of when it was asked, and
  # `labeledTranspose (labeledTranspose g)` restores `g`'s edge relation with each node's out-edges
  # re-sorted into `nodes` order.
  labeledTranspose = labeledDoor "labeledTranspose" (
    graph@{
      labeledEdges,
      nodes,
      ...
    }:
    let
      toKey = attrKey "labeledTranspose";
      incoming = builtins.groupBy (e: toKey e.target) (
        builtins.concatMap (
          from:
          map (e: {
            label = labelOf "labeledTranspose" from e;
            target = targetOf "labeledTranspose" from e;
            inherit from;
          }) (edgesAt "labeledTranspose" graph from)
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
        }) (incoming.${toKey id} or [ ]);
    }
  );
in
{
  inherit
    materialize
    materializeParents
    unionEdges
    intersectEdges
    differenceEdges
    selectEdges
    forgetLabels
    labeledTranspose
    ;
  # R6: not published — `lib/default.nix` strips it from the surface.
  threaded = {
    materialize = materializeAs;
    differenceEdges = differenceEdgesAs;
    # The labeled record's guarded reads by the reading surface's name, for `cyclicEdgesWhere`
    # (`partition.nix`).
    inherit edgesAt labelOf targetOf;
  };
  # The unchecked cores, for another file's internal callers (P2 §p2.3.2). Not published.
  cores = {
    forgetLabels = forgetLabelsCore;
  };
}
