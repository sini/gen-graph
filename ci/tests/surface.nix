# THE EXPORT SURFACE, PINNED BY CONTENTS.
#
# ★★ WHY CONTENTS AND NOT A COUNT. The constructs of this library migrate into a consolidated
# library later and the container does not, so a construct that is only reachable THROUGH a
# composition would have to be rebuilt at the fold, while a published one moves intact. This cell
# is what makes "published" a checked fact: a construct quietly demoted to an internal binding,
# reachable only as a side effect of calling `query`, takes this cell red rather than being noticed
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
# collation puts `coScc` and `ranksOf` in a different order, so a pin generated through a shell
# `sort` reads FALSE on a correct tree — a false red indistinguishable from a missing export.
{ genGraph, ... }:
let
  v = genGraph;

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
    "labeledFixtures"
    "labeledFrom"
    "labeledTranspose"
    "leaves"
    "materialize"
    "materializeParents"
    "mkDeclaredEdges"
    "mkEndpointProjection"
    "mkGraph"
    "mkNodeRef"
    "mkProjectionFindings"
    "mkSpawnedNodeRef"
    "nodeRefFindings"
    "pathLess"
    "pathsBetween"
    "phaseOrder"
    "query"
    "queryArrivals"
    "queryFold"
    "rankOf"
    "rankWordOf"
    "ranksOf"
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
    "wordLess"
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
  };
}
