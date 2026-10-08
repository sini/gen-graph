# THE EXPORT SURFACE, PINNED BY CONTENTS.
#
# ★★ WHY CONTENTS AND NOT A COUNT. The constructs of this library migrate into a consolidated
# library later and the container does not, so a construct that is only reachable THROUGH a
# composition would have to be rebuilt at the fold, while a published one moves intact. This cell
# is what makes "published" a checked fact: a construct quietly demoted to an internal binding,
# reachable only as a side effect of calling another surface, takes this cell red rather than being noticed
# at the fold. A rename or a drop is intentional and moves the list below in the same commit;
# anything else is drift.
#
# ★ WHY `entry.nix`'s SURFACE CELLS DO NOT COVER THIS. Those compare two COMPUTED surfaces — the
# standalone entry against the flake's — so both sides gain a new export together and the equality
# holds either way; their non-triviality bound is `> 40`, which cannot fire against a literal. This
# cell's operand is a LITERAL, and that is the whole difference.
#
# ★ ONE binding, read by BOTH cells — `entry.nix`'s rule, and the reason a `> 40` bound is NOT
# carried here: a control that does not touch this cell's operand is decoration that reads as
# arming. The control below reads the SAME `pinned` list at an input the main arm never supplies.
#
# ★ SORTED WITH NIX'S OWN `<`, NEVER A SHELL `sort`. Nix orders strings bytewise and a locale
# collation puts `coScc` and `compose` in a different order, so a pin generated through a shell
# `sort` reads FALSE on a correct tree — a false red indistinguishable from a missing export.
{ genGraph, genPrelude, ... }:
let
  v = genGraph;

  # THE LITERAL AGAINST ITS MODULE RECORD (den-hoag-9lg69). `lib/default.nix` publishes one
  # `inherit (modules.<m>)` clause per module, so a name a module gains and no clause lists is
  # unpublished silently, and a name listed under a module that lacks it fails only when demanded.
  # This is the check a `//` chain over the modules would have made by construction, run here
  # rather than at every load. A name listed twice in the literal is the evaluator's own parse
  # error; a name two modules export is refused below, where the old chain resolved it last-wins.
  # `key` and the four tombstones are the literal's own and no module's.
  nonModule = [
    "key"
    "query"
    "regex"
    "labeledFrom"
    "boundedBy"
  ];
  modules = import ../../lib/modules.nix { prelude = genPrelude; };
  namesOf = builtins.mapAttrs (_: builtins.attrNames);
  owners = builtins.concatLists (
    builtins.attrValues (
      builtins.mapAttrs (
        m:
        map (n: {
          inherit m n;
        })
      ) (namesOf modules)
    )
  );
  owed = map (o: o.n) owners;
  # Each name two modules export, once per exporting module, so the refusal names both.
  duplicated = builtins.filter (o: builtins.length (builtins.filter (n: n == o.n) owed) > 1) owners;
  published = builtins.filter (n: !(builtins.elem n nonModule)) (builtins.attrNames v);
  missing = builtins.filter (n: !(v ? ${n})) owed;
  extra = builtins.filter (n: !(builtins.elem n owed)) published;
  # Every published name forced: a name listed under a module that lacks it aborts here, naming it.
  forced = builtins.foldl' (a: n: builtins.seq (builtins.tryEval v.${n}).success a) null published;
  completeness = builtins.seq forced (
    if duplicated != [ ] then
      throw "gen-graph surface: exported by two modules: ${builtins.toJSON duplicated}"
    else if missing != [ ] || extra != [ ] then
      throw "gen-graph surface: the literal surface and the module record disagree: missing ${builtins.toJSON missing}, extra ${builtins.toJSON extra}"
    else
      "complete: ${toString (builtins.length published)} names"
  );

  pinned = [
    "ancestorsOf"
    "boundedBy"
    "canReach"
    "closureClass"
    "closureOf"
    "coScc"
    "compose"
    "condensation"
    "condensationClosure"
    "condensationOf"
    "coneRank"
    "cyclePaths"
    "cycles"
    "cyclicEdgesWhere"
    "declaredEdgesFindings"
    "dependents"
    "dependentsFrontier"
    "dependentsOf"
    "differenceEdges"
    "directDependents"
    "directDependentsOf"
    "entryAfter"
    "entryAnywhere"
    "entryBefore"
    "entryBetween"
    "expandPreorder"
    "fbNode"
    "fbWork"
    "field"
    "fields"
    "fixpoint"
    "fixtures"
    "foldPreorder"
    "foldReach"
    "forgetLabels"
    "fromRegistry"
    "fromScan"
    "hoistEdges"
    "impactOf"
    "intersectEdges"
    "isDeclaredEdges"
    "isNodeRef"
    "key"
    "labeledFixtures"
    "labeledFrom"
    "labeledTranspose"
    "leaves"
    "lowlink"
    "materialize"
    "materializeParents"
    "mkDeclaredEdges"
    "mkEndpointProjection"
    "mkGraph"
    "mkNodeRef"
    "mkProjectionFindings"
    "mkSpawnedNodeRef"
    "nodeRefFindings"
    "pathsBetween"
    "phaseOrder"
    "query"
    "reachableFrom"
    "reachableVia"
    "reachableWhere"
    "refName"
    "regex"
    "roots"
    "seededFixpoint"
    "select"
    "selectEdges"
    "selfReachable"
    "selfReachableVia"
    "topoOrder"
    "topoOrderKahn"
    "transitiveClosure"
    "transitiveReduction"
    "transpose"
    "unionEdges"
  ];
in
{
  flake.tests.surface = {
    test-the-published-surface = {
      expr = builtins.sort (a: b: a < b) (builtins.attrNames v) == pinned;
      expected = true;
    };

    # The same operand at an input the main arm never supplies: the pin minus its head name. A pin
    # that matched anything — or a comparison that had stopped comparing — would read `true` here.
    test-control-the-surface-pin-discriminates = {
      expr = builtins.sort (a: b: a < b) (builtins.attrNames v) == builtins.tail pinned;
      expected = false;
    };

    test-the-literal-surface-is-the-module-record = {
      expr = completeness;
      expected = "complete: 72 names";
    };

    # The check above runs in the suite and not at load because no caller can move a module's name
    # set: every name set is the same with `prelude`, the only formal, bound to a throw. A module
    # that computed its names from the formal would red this cell.
    test-module-name-sets-read-no-formal = {
      expr =
        namesOf (
          import ../../lib/modules.nix { prelude = throw "gen-graph surface: a name set read `prelude`"; }
        ) == namesOf modules;
      expected = true;
    };
  };
}
