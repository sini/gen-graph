# THE DECLARED DEPENDENCY RELATION — its element vocabulary, its contracted constructor, and the
# type that constructor mints.
#
# A consumer that DECLARES its dependency relation, rather than deriving it (`fromScan`, next door in
# `registry.nix`), hands the substrate a value it wrote by hand. Three things about that value are
# facts about the whole evaluation and cannot be recovered later: what it is (a relation, never a
# function of one), what its endpoints are (references the substrate minted, never strings a caller
# assembled), and when it is fixed (before the evaluation it describes exists). This module is where
# all three are settled, and it settles them at CONSTRUCTION because a construct's contract lives at
# its construction site — the same reason `endpoints.nix` gives for checking the projection's codomain
# where the projection is built rather than where it is read.
#
# THEORY. The deep force below is what makes a declared relation APPLICATIVE in the sense of Mokhov,
# Mitchell & Peyton Jones, *Build Systems à la Carte* (ICFP 2018, §3): dependencies are a function of
# the task description and not of running it. `fromScan` obtains that property structurally — the edge
# set is derived from item values that exist before any task runs. A DECLARED relation cannot obtain it
# structurally, because nothing stops an author writing a relation that closes over the very evaluation
# it is meant to order; the force is what converts that from a silent wrong answer into a divergence.
# The two constructors sit in one library for that reason: they are the derived and the declared halves
# of one property.
#
# THE ACCEPT-LIST, NOT A DENY-LIST. Nothing here is refused by enumerating what it is; things are
# admitted by satisfying what they must be, and a refusal names the CONJUNCT that failed. A roster of
# rejected shapes leaves gaps by construction — the shape nobody thought to enumerate is admitted — and
# that is a whole-ecosystem convention rather than a local taste: `gen-scope/lib/require-scope.nix`
# states it for the scope guard in the same words.
#
# THE REFERENCE IS A CONVENTION, NOT A CAPABILITY, AND THE STRENGTH IS STATED RATHER THAN IMPLIED.
# `isNodeRef` asks whether a value carries the tag this module's constructors write. That REFUSES BY
# NAME every ACCIDENTAL construction — a raw string endpoint, a typo, an id computed from something,
# a value carried in from another graph — which is the whole of the defect class that occurs. It does
# NOT refuse DELIBERATE circumvention: an author who writes the tagged record out by hand defeats it,
# and that is out of threat model rather than overlooked (nothing here needs cryptographic integrity,
# only distinctness). This is the `mkOverride`-class convention, relied on exactly as `gen-scope`'s own
# `mkKind`/`mkClaim` markers are relied on today, and its refusal names the CONSTRUCTOR — "was not
# built by mkNodeRef" — rather than the shape, so a reader is told the door they missed.
#
# `id` IS AN IDENTIFIER, NOT NECESSARILY AN IDENTITY. Every node carries an identifier or it cannot be
# an edge endpoint; identity-bearing kinds ADDITIONALLY carry a derived identity minted elsewhere. A
# reference wraps whichever the node has, so nothing in this module depends on a mint.
#
# THE TWO CONSTRUCTION ROUTES ARE DISJOINT AND JOINTLY TOTAL over the references that can exist, which
# is what lets a codomain condition be stated without a subset check anywhere downstream.
#   ROUTE 1, AUTHOR-WRITTEN (`mkNodeRef`) — validated at construction against the REGISTRATION set, the
#     declared vertex order, which is well-defined before any equation runs. A materialization walk
#     seeded from that order evaluates every declared node whatever a consumer's own equations return,
#     so the evaluated node set CONTAINS the registration set and the check is superset-safe: a
#     reference this route admits is a node the evaluator will have.
#   ROUTE 2, SPAWN-MINTED (`mkSpawnedNodeRef`) — the substrate builds it at spawn time for a node it
#     just created. No author writes it, so no validation against a registration set is owed or
#     possible; a node arriving through this channel is not in the registration set by definition.
#
# THE ORDER OF THE CHECKS IS THE MECHANISM, NOT A STYLE CHOICE — the same staging `endpoints.nix`
# spells out. Naming an offender in a refusal INTERPOLATES it, and interpolating a non-string is a
# COERCION error rather than a `throw`: uncatchable, so an oracle written to detect that mode could
# never fire. Therefore an identifier is tested for STRINGNESS before it is tested for MEMBERSHIP, and
# an endpoint is named by POSITION AND TYPE while only the membership refusal names an id — because
# only there is one known to be a string.
#
# WHAT IS NOT DEFAULTED, AND THAT IS THE POINT. `mkDeclaredEdges` takes the relation POSITIONALLY, so
# there is no `? [ ]` hole to fall through: a caller with nothing to declare passes an empty relation,
# which is a different thing from silence. `mkGraph` next door does default its `edges`, deliberately —
# it takes an edge set a caller already holds and derives a graph from it, and asserts nothing about
# the caller's obligation to have one.
let
  _refMarker = "gen-graph/node-ref";
  _edgeSetMarker = "gen-graph/declared-edges";

  # ── THE REFUSALS, WRITTEN ONCE AND SHARED BY BOTH SURFACES OF EACH CONSTRUCTOR ──
  # Each validator RETURNS these and each constructor THROWS the first of them, so the two surfaces
  # cannot come to state different contracts: the throw IS the first finding, never a second copy of
  # the same tests. An assertion belongs on the RETURNED message rather than on a caught throw — a
  # caught throw proves only that something refused, never that it refused for the reason under test.

  # Names the type and never the value: the value is not a string, and interpolating it is the
  # coercion abort the staging above exists to avoid.
  _notAnIdentifier =
    who: v: "gen-graph.${who}: got ${builtins.typeOf v}, expected a node identifier (a string)";

  # The one node-reference refusal that may name an id, because by this stage one is known to exist.
  _notRegistered =
    id:
    "gen-graph.mkNodeRef: '${id}' is not a node of the registration set; an author-written reference names a declared node";

  _notARelation =
    v:
    "gen-graph.mkDeclaredEdges: got ${builtins.typeOf v}, expected either a list of { from = <node reference>; to = <node reference>; } edges or an attrset from a node's canonical name to a list of node references";

  _elementNotAnEdge =
    i: e:
    "gen-graph.mkDeclaredEdges: element ${toString i}: got ${builtins.typeOf e}, expected { from = <node reference>; to = <node reference>; }";

  _elementMissingField =
    i: field:
    "gen-graph.mkDeclaredEdges: element ${toString i}: no '${field}' field; expected { from = <node reference>; to = <node reference>; }";

  _endpointNotARef =
    i: field: v:
    "gen-graph.mkDeclaredEdges: element ${toString i}, '${field}': got ${builtins.typeOf v}, which was not built by mkNodeRef";

  _keyNotAList =
    name: v:
    "gen-graph.mkDeclaredEdges: key '${name}': got ${builtins.typeOf v}, expected a list of node references";

  _keyElementNotARef =
    name: i: v:
    "gen-graph.mkDeclaredEdges: key '${name}' element ${toString i}: got ${builtins.typeOf v}, which was not built by mkNodeRef";

  _indices = xs: builtins.genList (i: i) (builtins.length xs);

  _isNodeRef = v: (v._type or null) == _refMarker;

  # The reference -> string projection, bound here so the normalization below and the published
  # `refName` are ONE definition. A second inlined `ref.id` would be a second route to a string, and
  # the whole point of the projection is that there is exactly one.
  _refName = ref: ref.id;

  _nodeRefFindings =
    isRegistered: id:
    if !(builtins.isString id) then
      [ (_notAnIdentifier "mkNodeRef" id) ]
    else if !(isRegistered id) then
      [ (_notRegistered id) ]
    else
      [ ];

  # ONE conjunct per declared form, each checked to REFERENCE DEPTH. Every violating position reports
  # rather than only the first, because a validator that stops at one hides the rest of the same
  # defect. The ATTRSET form's KEYS are not checked and cannot be: a key is a canonical name — the
  # string `refName` projects a reference to — and Nix attrset keys are strings already, so there is
  # nothing left for a check to observe. The convention is real and it is the caller's; stating it
  # here as if it were enforced would be the kind of unearned claim this module exists to avoid.
  _relationFindings =
    relation:
    if builtins.isList relation then
      builtins.concatMap (
        i:
        let
          e = builtins.elemAt relation i;
        in
        if !(builtins.isAttrs e) then
          [ (_elementNotAnEdge i e) ]
        else
          builtins.concatMap
            (
              field:
              if !(e ? ${field}) then
                [ (_elementMissingField i field) ]
              else if !(_isNodeRef e.${field}) then
                [ (_endpointNotARef i field e.${field}) ]
              else
                [ ]
            )
            [
              "from"
              "to"
            ]
      ) (_indices relation)
    else if builtins.isAttrs relation then
      builtins.concatMap (
        name:
        let
          value = relation.${name};
        in
        if !(builtins.isList value) then
          [ (_keyNotAList name value) ]
        else
          builtins.concatMap (
            i:
            let
              e = builtins.elemAt value i;
            in
            if !(_isNodeRef e) then [ (_keyElementNotARef name i e) ] else [ ]
          ) (_indices value)
      ) (builtins.attrNames relation)
    else
      [ (_notARelation relation) ];

  # THE NORMALIZATION — what the constructor DOES to a relation that satisfies the accept-list, which
  # is a different question from what it accepts and is answered here rather than left to a caller.
  # The list form becomes the attrset index the published relation reads: `groupBy` on the SOURCE'S
  # NAME, each group mapped to its targets' NAMES. That is `mkGraph`'s own `edgeIndex` one file over,
  # and `refName` is load-bearing in it — Nix attrset keys must be strings, so grouping on a tagged
  # record does not typecheck and the list form would be unbuildable without the projection.
  #
  # DUPLICATE SOURCES ACCUMULATE. `groupBy` collects every edge out of a source; a `listToAttrs`-based
  # derivation keeps the FIRST binding for a repeated key and DROPS the rest with no signal (measured;
  # it is not the last, which is the plausible guess) — under-declaration by another route. Repeated identical edges are NOT deduplicated — that is left to the consumer, since a
  # repeated edge is not an under-declaration and no reader of this relation has been measured to
  # need uniqueness. `mkGraph` takes the other choice for its own index and applies `unique`; the two
  # differ deliberately.
  _normalize =
    relation:
    if builtins.isList relation then
      builtins.mapAttrs (_: es: map (e: _refName e.to) es) (
        builtins.groupBy (e: _refName e.from) relation
      )
    else
      builtins.mapAttrs (_: refs: map _refName refs) relation;
in
{
  # isNodeRef : a -> bool — does this value carry the tag only this module's constructors write?
  isNodeRef = _isNodeRef;

  # refName : <nodeRef> -> string — the identifier the reference wraps. THE ONLY route from a
  # reference to a string: every site needing an attrset key, a membership comparison against a
  # substrate id, or a message fragment goes through it.
  refName = _refName;

  # mkNodeRef : { isRegistered } -> id -> <nodeRef>   (ROUTE 1, author-written)
  #
  # The membership authority arrives as a PARAMETER because it is a fact about a registered substrate
  # and this library has no evaluator and must not acquire one — its single input is gen-prelude. A
  # private copy of the node set kept here would be correct exactly as long as someone kept two copies
  # in step, and the failure when they stop agreeing is silent.
  mkNodeRef =
    { isRegistered }:
    id:
    let
      findings = _nodeRefFindings isRegistered id;
    in
    if findings == [ ] then
      {
        _type = _refMarker;
        inherit id;
      }
    else
      throw (builtins.head findings);

  # nodeRefFindings : { isRegistered } -> id -> [string] — the same contract as a VALUE, so a caller
  # or an oracle reads the message the constructor would throw.
  nodeRefFindings = { isRegistered }: id: _nodeRefFindings isRegistered id;

  # mkSpawnedNodeRef : id -> <nodeRef>   (ROUTE 2, substrate-minted at spawn time)
  #
  # No registration check: the node did not exist when the registration set was fixed, which is what
  # spawning means. The STRINGNESS check is not a weakened membership check and does not stand in for
  # one — it is what keeps `refName`'s codomain a string, and a non-string leaking through here would
  # surface downstream as a coercion abort at a `groupBy` key rather than as any refusal.
  mkSpawnedNodeRef =
    id:
    if builtins.isString id then
      {
        _type = _refMarker;
        inherit id;
      }
    else
      throw (_notAnIdentifier "mkSpawnedNodeRef" id);

  # mkDeclaredEdges : relation -> <declaredEdges>
  #
  # The contracted entry. THE FORCE IS `builtins.deepSeq` AND THE DEPTH IS PART OF THE CONTRACT, not
  # an implementation detail: a WHNF force satisfies every other word of this clause and leaves the
  # knot writable. Under the deep force a relation that reaches back into the evaluation it orders
  # cannot be produced — the force demands the value and every sub-value transitively, the value
  # demands the evaluation, the evaluation demands the force. That failure is `infinite recursion
  # encountered`, a divergence carrying no name of ours and one `tryEval` does not contain, so there
  # is no cell for the knot itself; what is assertable is the DEPTH that causes it, by its one
  # observable consequence — a throw below the tag check fires at construction rather than at first
  # read. The accept-list already reaches endpoint depth, so the depth the force ADDS is everything
  # BELOW and BESIDE an endpoint: a reference's own `id`, and the extra fields an element is permitted
  # to carry.
  #
  # THE FORCE'S SUBJECT IS THE RELATION AND NOTHING ELSE. It is applied to the declared relation, never
  # to a node's content, a caller's configuration or anything the relation merely sits beside — a force
  # that reached those would change the cost class of the whole evaluation. Here that is structural
  # rather than promised: the relation is the ONLY thing this constructor is handed.
  #
  # COST: an eager traversal of the whole declared relation at construction, O(|E|) in the number of
  # declared edges, paid once, before any attribute is demanded. It is unconditional; there is no
  # setting that disables it. What is forced is declaration-sized inert data, and that is a property
  # of the subject above rather than a hope.
  #
  # EXTRA FIELDS ON AN ELEMENT ARE ADMITTED AND IGNORED — `{ from; to; extra = 42; }` passes and the
  # normalization reads only the pair. `fromScan` builds its edge records with four fields, so a
  # caller holding an extended edge record is the normal case in this very library.
  mkDeclaredEdges =
    relation:
    let
      findings = _relationFindings relation;
      index = _normalize relation;
    in
    builtins.deepSeq relation (
      if findings != [ ] then
        throw (builtins.head findings)
      else
        {
          _type = _edgeSetMarker;
          inherit index;
          dependencies = id: index.${id} or [ ];
        }
    );

  # declaredEdgesFindings : relation -> [string] — the accept-list as a VALUE. Nothing in the
  # production path forces it, so it alters no result and is not a rule any consumer must obey.
  declaredEdgesFindings = _relationFindings;

  # isDeclaredEdges : a -> bool — THE SHARED TYPE. A contract enforced only inside the fold that
  # reads the relation is bypassed by any caller who hand-assembles the context, and callers do
  # exactly that. So the contract belongs to a constructor and the type is what an entry point
  # accepts in place of a bare attrset: a consumer that takes a second, caller-supplied edge set
  # admits only what this module minted, and states its own refusal naming its own entry point.
  # The predicate is NOMINAL and not structural on purpose — a hand-assembled attrset carrying an
  # `index` and a `dependencies` has the right SHAPE and is precisely the bypass.
  isDeclaredEdges = v: (v._type or null) == _edgeSetMarker;
}
