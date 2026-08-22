# THE ENDPOINT PROJECTION — a structural attribute RECORD read as an edge relation.
#
# A substrate's structural attributes arrive as `id -> { name -> value }`: an attribute-name-indexed
# record, which is not even the arity of an edge set. This module is the projection that closes that
# gap, `id -> [id]`. It is a RELATIONAL projection — π_endpoints ∘ σ_structural — and a relational
# projection is SET-VALUED, so the result is deduplicated BY CONSTRUCTION rather than repaired at a
# consumer. That is the same set-of-targets contract `forgetLabels` states for the labeled half and
# `mkGraph` states for the registry half; a projection that leaked multiplicity would hand the
# global surfaces a number none of them has a meaning for.
#
# THEORY. The relation projected is van Antwerpen et al. (2018), *Scopes as Types*, Fig. 1's
# `edges  Edges ::= s —l→ s` with the label FORGOTTEN at the projection: the attribute name is `l`,
# and `concatMap` flattens it away. That debt to the primary is deliberate and is paid down by
# `labeledFrom` + `forgetLabels`, already in this library — the re-entry trigger is the first
# consumer that needs to know WHICH relation an edge came from. Building a labelled relation today
# only to forget it at its single call site is machinery no oracle could fail.
#
# WHY THE FAMILY RULE AND THE MEMBERSHIP AUTHORITY ARRIVE AS PARAMETERS. Both are facts about an
# EVALUATED substrate, and this library has no evaluator and must not acquire one — its single
# input is gen-prelude. A constructor taking them as parameters and emitting a value mints that
# value inside the eval doing the constructing, so what it asserts is owned rather than borrowed
# (ADR-0014's constructing arm). The alternative — a private copy of the child-bearing names kept
# here — would be correct exactly as long as someone kept the two copies in step, and the failure
# when they stop agreeing is SILENT: the projection either reads `attrNames` of a value that was
# never keyed by child id, or consumes an attrset of records as if it were a list of endpoints.
# Two literals agreeing is a coincidence.
#
# THE TWO FAMILIES. `childBearing` names the structural attributes whose value is an attrset KEYED
# BY CHILD NODE ID; their endpoints are its KEYS. Every other structural attribute IS a list of node
# references; its endpoints are ITSELF. `endpointsOf` is total over the partition in exactly these
# two cases, which is why the discriminator is a predicate over the name rather than an enumeration.
#
# THE CODOMAIN CONTRACT, AND WHY IT IS CHECKED HERE. A construct's codomain contract lives at its
# CONSTRUCTION SITE; a consumer-site check guards a path, not a construct. The child-bearing
# families are contracted upstream — a substrate that selects its children among registered nodes
# refuses a non-node by name, and a substrate that DESCENDS what it produced closes the other by
# definition rather than by a check — so a check there asks a question already answered. The
# remaining family is the CONSUMER'S own equation, and only a contract can close it: its value must
# be a list of ids, each a member of the evaluated node set, refused by name otherwise.
#
# THE ORDER OF THE TWO HALVES IS THE MECHANISM, NOT A STYLE CHOICE. Naming a non-string offender in
# a refusal message INTERPOLATES it, and interpolating a non-string is a COERCION error rather than
# a `throw` — uncatchable, so an oracle written to detect that mode could never fire, and the check
# would have converted a silent defect into an uncatchable abort. Therefore: the whole value is
# tested with `isList` before anything is mapped; each element with `isString` before it is
# interpolated; and only then is membership asked. Each stage names only what it can LEGITIMATELY
# name — the shape refusals name the reading node, the family, and TYPE-AND-POSITION, while only
# the membership refusal names an id, because only there is one known to exist. A refusal at a
# boundary naming the mark that caused it, rather than surprising the query author, is ADR-0026's
# shape.
#
# FAIL-CLOSED, AND THE COST THAT BUYS. "Is a node" is a claim about the WHOLE graph, not about the
# node being read, so the projection's answer is a GLOBAL claim and forcing the node set is its
# price. One broken structural equation anywhere therefore refuses every projection read. That is
# the right DIRECTION of failure and not a tolerated one: a projection that answered while the
# authority it checks against was unavailable would assert a membership it could not verify, which
# is the shape ADR-0026 rejects by name — it fails open, so that silence becomes access. Cost never
# constrains correctness (ADR-0032 ruling 2).
{ prelude }:
let
  # THE THREE REFUSALS, WRITTEN ONCE AND SHARED BY BOTH SURFACES BELOW. The validator RETURNS these
  # and the projection THROWS the first of them, so the two surfaces cannot come to state different
  # contracts: the throw IS the first finding, never a second copy of the same three tests.
  _notAList =
    id: name: value:
    "gen-graph.mkEndpointProjection: node '${id}' structural attribute '${name}': got ${builtins.typeOf value}, expected a list of node ids";

  # Names the POSITION and the TYPE. It must not name the element: the element is not a string, and
  # interpolating it is the coercion abort this staging exists to avoid.
  _notAnId =
    id: name: i: e:
    "gen-graph.mkEndpointProjection: node '${id}' structural attribute '${name}' element ${toString i}: got ${builtins.typeOf e}, expected a node id";

  # The one refusal that may name an id, because by this stage one is known to exist.
  _notANode =
    id: name: e:
    "gen-graph.mkEndpointProjection: node '${id}' structural attribute '${name}': '${e}' is not a node of the evaluated graph";

  # The contract over ONE non-child-bearing attribute, as findings — `[ ]` when it is clean. Ordered
  # by stage: a non-list yields exactly one finding and no element is reached at all; otherwise each
  # element is tested for SHAPE before it is tested for MEMBERSHIP, so nothing that has not been
  # established to be a string is ever interpolated. Every violating element reports, rather than
  # only the first, because a validator that stops at one hides the rest of the same defect.
  _family2Findings =
    isNode: id: name: value:
    if !(builtins.isList value) then
      [ (_notAList id name value) ]
    else
      builtins.concatMap (
        i:
        let
          e = builtins.elemAt value i;
        in
        if !(builtins.isString e) then
          [ (_notAnId id name i e) ]
        else if !(isNode e) then
          [ (_notANode id name e) ]
        else
          [ ]
      ) (builtins.genList (i: i) (builtins.length value));

  # The contract's DOMAIN: the non-child-bearing structural names, and nothing else. The gate is
  # part of the definition rather than an optimisation, and it reads the injected predicate rather
  # than any literal name — a gate written against a literal would admit the child-bearing family
  # whose name it failed to guess.
  _governed = childBearing: sa: builtins.filter (name: !(childBearing name)) (builtins.attrNames sa);
in
{
  # mkEndpointProjection : { childBearing, isNode } -> (id -> structuralRecord) -> id -> [id]
  #
  # The published projection. Refuses by name on a governed attribute that is not a list of node
  # ids, and emits a SET.
  mkEndpointProjection =
    { childBearing, isNode }:
    structuralAttributesOf: id:
    let
      sa = structuralAttributesOf id;
      endpointsOf =
        name:
        if childBearing name then
          builtins.attrNames sa.${name}
        else
          let
            findings = _family2Findings isNode id name sa.${name};
          in
          if findings == [ ] then sa.${name} else throw (builtins.head findings);
    in
    prelude.unique (builtins.concatMap endpointsOf (builtins.attrNames sa));

  # mkProjectionFindings : { childBearing, isNode } -> (id -> structuralRecord) -> id -> [string]
  #
  # The same contract as a VALUE. Nothing in the production path forces it, so it alters no
  # production result and is not a rule any consumer must obey; forcing it reports every governed
  # attribute of this node that violates the codomain contract, and `[ ]` when none does. An
  # assertion belongs on this returned message rather than on a caught throw — a caught throw
  # proves only that something refused, never that it refused for the reason under test.
  mkProjectionFindings =
    { childBearing, isNode }:
    structuralAttributesOf: id:
    let
      sa = structuralAttributesOf id;
    in
    builtins.concatMap (name: _family2Findings isNode id name sa.${name}) (_governed childBearing sa);
}
