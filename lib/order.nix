# Ordering front-door — home-manager-style DAG entries (before/after) resolved to a
# forward, producers-first phase order over the condensation. This is the ergonomic
# authoring layer atop `condensation`; it absorbs what gen-dispatch's dag.nix used to own
# (entry*/topoSort) so gen-dispatch can be the pure dispatch STEP (no ordering).
# THEORY: home-manager dag idiom (generalized strings-with-deps) over Mokhov 2017 §4
# quotient-graph topological enumeration. `phaseOrder` returns A valid topological order
# (reverse of condensation.bottomUp); its SCC tie-break is closure-cardinality+name
# (global.nix), which may differ from nixpkgs-toposort's attr-name seed for genuinely
# INDEPENDENT phases — but a consumer that threads a phase's effect into context only
# AFTER the phase (e.g. gen-dispatch.dispatch) is output-invariant across any valid topo
# order, so this is sound for well-formed phase DAGs.
{ prelude }:
let
  global = import ./global.nix { inherit prelude; };

  entryBetween = before: after: { inherit before after; };
  entryAnywhere = entryBetween [ ] [ ];
  entryAfter = after: entryBetween [ ] after;
  entryBefore = before: entryBetween before [ ];

  # after=[d] on n => edge d->n (d precedes n); before=[t] on n => edge n->t (n precedes t).
  phaseOrder =
    entries:
    let
      names = builtins.attrNames entries;
      fromAfter = prelude.concatMap (
        n:
        map (d: {
          from = d;
          to = n;
        }) (entries.${n}.after or [ ])
      ) names;
      fromBefore = prelude.concatMap (
        n:
        map (t: {
          from = n;
          to = t;
        }) (entries.${n}.before or [ ])
      ) names;
      grouped = builtins.groupBy (x: x.from) (fromAfter ++ fromBefore);
      edges = id: map (x: x.to) (grouped.${id} or [ ]);
      c = global.condensation {
        nodes = names;
        inherit edges;
      }; # c.reps == bottomUp (reverse-topo)
      # A cycle surfaces as a non-singleton SCC; a self-loop (n after n) is a singleton SCC
      # so catch it directly — preserving gen-dispatch dag.nix's throw-on-cycle contract.
      nonSingleton = builtins.filter (r: builtins.length (c.members r) > 1) c.reps;
      selfLoops = builtins.filter (n: builtins.elem n (edges n)) names;
    in
    if nonSingleton != [ ] || selfLoops != [ ] then
      throw "gen-graph.phaseOrder: cyclic ordering constraints: ${
        builtins.toJSON (map c.members nonSingleton ++ map (n: [ n ]) selfLoops)
      }"
    else
      # reverse bottomUp + flatten singletons => forward producers-first order
      prelude.foldl' (acc: r: [ (builtins.head (c.members r)) ] ++ acc) [ ] c.reps;
in
{
  inherit
    entryAnywhere
    entryAfter
    entryBefore
    entryBetween
    phaseOrder
    ;
}
