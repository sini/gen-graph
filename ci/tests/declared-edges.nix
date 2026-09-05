# THE DECLARED RELATION'S ORACLES.
#
# Every cell below names the SEEDED DEFECT it refuses, and each seed is CONSTRUCTED IN THIS FILE and
# evaluated in the same run as the cell that passes clean — a guard whose seed is only described has
# not been shown to discriminate. The seeds are the wrong constructions an implementer plausibly
# reaches for: the deny-list that asks `isFunction`, the force weakened by one word, the force at the
# interposed per-value depth, the `listToAttrs` normalization, and the STRUCTURAL type predicate.
#
# THE TWO INSTRUMENTS ARE NOT INTERCHANGEABLE, AND USING THE WRONG ONE MAKES A PAIR AGREE.
# `refusedAtConstruction` forces the constructor's result to WHNF ONLY. That is what makes the force
# cells measure the CONSTRUCTOR'S force rather than the probe's: written with `deepSeq`, the probe
# itself would reach the seeded throw and BOTH arms would read `true`, which is a pair that has
# measured nothing. `didThrow` deep-forces and is used only where the subject is a value, never where
# the subject is a depth.
#
# WHY THE ILL-TYPING CELLS ASSERT MESSAGES RATHER THAN CAUGHT THROWS. A caught throw proves only that
# something refused, never that it refused for the reason under test — and every refusal here is a
# `throw` of the FIRST finding, so the validator surface and the constructor cannot come to state
# different contracts.
{ genGraph, ... }:
let
  inherit (genGraph)
    mkNodeRef
    mkSpawnedNodeRef
    nodeRefFindings
    isNodeRef
    refName
    mkDeclaredEdges
    declaredEdgesFindings
    isDeclaredEdges
    ;

  # Deep-forces: for cells whose subject is a VALUE.
  didThrow = v: !(builtins.tryEval (builtins.deepSeq v true)).success;

  # WHNF only: for cells whose subject is a DEPTH. See the header.
  refusedAtConstruction = v: !(builtins.tryEval (builtins.seq v true)).success;

  # ── THE REGISTRATION SET, AS THE SUBSTRATE WOULD SUPPLY IT ──
  # The declared vertex order, fixed before any equation runs. `spawned` is deliberately absent from
  # it: route 2 exists precisely because a spawned node is not in the set route 1 checks against.
  registered = [
    "child"
    "parent"
    "sibling"
  ];
  isRegistered = id: builtins.elem id registered;
  authority = { inherit isRegistered; };
  ref = mkNodeRef authority;

  # ── THE FIXTURES ──
  listForm = [
    {
      from = ref "child";
      to = ref "parent";
    }
  ];

  # Two edges out of ONE source. The whole difference between the specified grouping and the
  # plausible-but-lossy one is visible here and nowhere else.
  listFormSharedSource = [
    {
      from = ref "child";
      to = ref "parent";
    }
    {
      from = ref "child";
      to = ref "sibling";
    }
  ];

  attrsetForm = {
    child = [
      (ref "parent")
      (ref "sibling")
    ];
  };

  # Fields beyond the pair are admitted and ignored — `fromScan` in this very library builds edge
  # records with four fields, so an extended record is the normal case rather than an abuse.
  extraFieldForm = [
    {
      from = ref "child";
      to = ref "parent";
      extra = 42;
    }
  ];

  # ── THE ACCIDENTAL AND COMPUTED ENDPOINTS ──
  # A bare string literal, and an id assembled by ordinary string operations. Both are what an author
  # writes when they have not gone through the constructor, and neither carries the tag.
  bareStringEndpoint = {
    child = [ "parent" ];
  };
  computedEndpoint = {
    child = [ ("par" + "ent") ];
  };
  bareStringInListForm = [
    {
      from = "child";
      to = "parent";
    }
  ];

  # ── THE CALLABLE FORMS ──
  lambdaRelation = _: [ ];
  # Callable, and `isFunction`-FALSE. Under a deny-list asking "is this a function?" it is admitted,
  # seals with domain ["__functor"], and awards every node the maximal claim silently.
  functorRelation = {
    __functor = _self: _id: [ ];
  };

  # ── THE DEPTH SEEDS ──
  # Both sit BELOW what the accept-list reaches. The accept-list checks to REFERENCE depth — it forces
  # an element's tag — so a throw AT endpoint position refuses under every force depth and could not
  # discriminate one. What the deep force adds is everything below and beside an endpoint.

  # (1) A throw in a PERMITTED EXTRA FIELD. Every endpoint here is properly minted and the element is
  # admitted by the extra-field latitude, so nothing but the force reaches it.
  depthSeedExtraField = [
    {
      from = ref "child";
      to = ref "parent";
      extra = throw "gen-graph: the extra field was forced";
    }
  ];

  # (2) A throw in a reference's own `id`, one level below the tag the accept-list checks. The record
  # is written out by hand, which is the deliberate circumvention the convention states is out of
  # threat model — and that is exactly why it is the sharpest probe of what the FORCE adds beyond the
  # CHECK: no constructor would mint this.
  depthSeedRefId = {
    child = [
      {
        _type = "gen-graph/node-ref";
        id = throw "gen-graph: the reference's identifier was forced";
      }
    ];
  };

  # The shipped constructor with ONE WORD changed, twice. The accept-list and the refusal are
  # identical in all three; the returned value is a stub because no cell forces past WHNF, so what
  # the triple varies is the FORCE and nothing else.
  seedConstructorForcedBy =
    force: relation:
    let
      findings = declaredEdgesFindings relation;
    in
    force relation (if findings != [ ] then throw (builtins.head findings) else true);

  # WHNF: `deepSeq` -> `seq`.
  seedWhnf = seedConstructorForcedBy builtins.seq;

  # The interposed depth — what a competent implementer writes when told "force the values". It
  # satisfies "every value of the relation is demanded" and still admits everything below one level.
  seedPerValue = seedConstructorForcedBy (
    relation: result:
    builtins.foldl' (acc: v: builtins.seq v acc) result (
      if builtins.isAttrs relation then builtins.attrValues relation else relation
    )
  );

  # ── THE NORMALIZATION SEED ──
  # `listToAttrs` keeps the FIRST binding for a repeated key and drops the rest with no signal,
  # which is under-declaration by another route.
  seedListToAttrs =
    relation:
    builtins.listToAttrs (
      map (e: {
        name = refName e.from;
        value = [ (refName e.to) ];
      }) relation
    );

  # ── THE TYPE SEED ──
  # The STRUCTURAL predicate. A hand-assembled edge set has the right shape and no tag, so this
  # admits precisely the bypass the nominal type exists to close.
  seedShapePredicate = v: (v ? index) && (v ? dependencies);
  handAssembled = {
    index = {
      child = [ "parent" ];
    };
    dependencies = _id: [ ];
  };

  declared = mkDeclaredEdges attrsetForm;
in
{
  flake.tests.declared-edges = {

    # ── THE NODE REFERENCE — the tagged-reference convention ──
    test-a-minted-reference-is-a-tagged-record = {
      expr = ref "parent";
      expected = {
        _type = "gen-graph/node-ref";
        id = "parent";
      };
    };
    test-refname-is-the-route-from-a-reference-to-a-string = {
      expr = refName (ref "parent");
      expected = "parent";
    };
    # A raw string is not a reference. This is the whole of the accidental class in one line.
    test-a-raw-string-is-not-a-reference = {
      expr = isNodeRef "parent";
      expected = false;
    };
    test-control-a-minted-reference-is-a-reference = {
      expr = isNodeRef (ref "parent");
      expected = true;
    };
    # THE HONEST STRENGTH, ASSERTED RATHER THAN HIDDEN. A hand-written tag defeats the convention.
    # This is out of threat model by ruling — nothing here needs cryptographic integrity, only
    # distinctness — and a cell that pretended otherwise would be pinning a law we do not have.
    test-deliberate-circumvention-is-admitted-and-that-is-stated = {
      expr = isNodeRef {
        _type = "gen-graph/node-ref";
        id = "ghost";
      };
      expected = true;
    };

    # ── ROUTE 1 · AUTHOR-WRITTEN, VALIDATED AGAINST THE REGISTRATION SET ──
    test-an-unregistered-id-is-refused-by-name-at-construction = {
      expr = nodeRefFindings authority "ghost";
      expected = [
        "gen-graph.mkNodeRef: 'ghost' is not a node of the registration set; an author-written reference names a declared node"
      ];
    };
    test-control-a-registered-id-has-no-findings = {
      expr = nodeRefFindings authority "parent";
      expected = [ ];
    };
    # The refusal is a throw at the constructor, not only a finding at the validator.
    test-control-the-unregistered-refusal-really-throws = {
      expr = didThrow (ref "ghost");
      expected = true;
    };
    # SHAPE BEFORE MEMBERSHIP, and the message names the TYPE and never the value: interpolating a
    # non-string is a coercion abort, and a cell written to detect that mode could never fire.
    test-a-non-string-identifier-is-refused-without-being-interpolated = {
      expr = nodeRefFindings authority 42;
      expected = [
        "gen-graph.mkNodeRef: got int, expected a node identifier (a string)"
      ];
    };

    # ── ROUTE 2 · SPAWN-MINTED ──
    # A spawned node is NOT in the registration set, so route 1 would refuse it — which is why the
    # routes are two and not one.
    test-a-spawned-reference-needs-no-registration-set = {
      expr = mkSpawnedNodeRef "spawned";
      expected = {
        _type = "gen-graph/node-ref";
        id = "spawned";
      };
    };
    test-control-route-1-refuses-the-same-id = {
      expr = didThrow (ref "spawned");
      expected = true;
    };
    # The stringness check is not a weakened membership check; it keeps `refName`'s codomain a string.
    test-a-spawned-reference-still-refuses-a-non-string-identifier = {
      expr = didThrow (mkSpawnedNodeRef 42);
      expected = true;
    };

    # ── THE ACCEPT-LIST · BOTH DECLARED FORMS ARE ADMITTED ──
    test-the-list-form-is-accepted-and-normalized = {
      expr = (mkDeclaredEdges listForm).dependencies "child";
      expected = [ "parent" ];
    };
    test-the-attrset-form-is-accepted-and-normalized = {
      expr = declared.dependencies "child";
      expected = [
        "parent"
        "sibling"
      ];
    };
    # DOMAIN CLOSURE: attrset values are lazy but KEYS are eager, so the set of ids the declaration
    # ranges over is fixed the moment the value exists, and it is observable.
    test-the-domain-is-fixed-and-published = {
      expr = builtins.attrNames declared.index;
      expected = [ "child" ];
    };
    # An undeclared node answers empty, so a non-empty answer above is the declaration and not a ⊤.
    test-control-an-undeclared-node-answers-empty = {
      expr = declared.dependencies "parent";
      expected = [ ];
    };
    # An EMPTY relation is accepted and is a different thing from silence — there is no default to
    # fall through, because the constructor takes its relation positionally.
    test-control-an-empty-relation-is-accepted = {
      expr = (mkDeclaredEdges { }).dependencies "child";
      expected = [ ];
    };

    # ── THE NORMALIZATION · DUPLICATE SOURCES ACCUMULATE ──
    test-duplicate-sources-accumulate = {
      expr = (mkDeclaredEdges listFormSharedSource).dependencies "child";
      expected = [
        "parent"
        "sibling"
      ];
    };
    # The seed drops the second edge and returns a fully plausible one-element answer.
    test-seed-listToAttrs-drops-every-edge-but-the-first = {
      expr = (seedListToAttrs listFormSharedSource).child;
      expected = [ "parent" ];
    };
    # Repeated identical edges are NOT deduplicated; that is left to the consumer deliberately.
    test-repeated-edges-are-not-deduplicated = {
      expr =
        (mkDeclaredEdges [
          {
            from = ref "child";
            to = ref "parent";
          }
          {
            from = ref "child";
            to = ref "parent";
          }
        ]).dependencies
          "child";
      expected = [
        "parent"
        "parent"
      ];
    };

    # ── THE ACCIDENTAL AND COMPUTED ENDPOINT IS REFUSED BY NAME ──
    # This is the cell that matters: a happy path proves nothing about a convention whose whole job
    # is refusal. The message names the CONSTRUCTOR the value did not come from, not the shape.
    test-a-bare-string-endpoint-is-refused-by-name = {
      expr = declaredEdgesFindings bareStringEndpoint;
      expected = [
        "gen-graph.mkDeclaredEdges: key 'child' element 0: got string, which was not built by mkNodeRef"
      ];
    };
    # A COMPUTED endpoint fails identically — it is a string however it was assembled, and an id
    # computed from this fold's own result is the sharpest instance of the class.
    test-a-computed-endpoint-is-refused-by-name = {
      expr = declaredEdgesFindings computedEndpoint;
      expected = [
        "gen-graph.mkDeclaredEdges: key 'child' element 0: got string, which was not built by mkNodeRef"
      ];
    };
    # The same defect in the other declared form, named by POSITION AND FIELD.
    test-a-bare-string-endpoint-in-the-list-form-is-refused-by-name = {
      expr = declaredEdgesFindings bareStringInListForm;
      expected = [
        "gen-graph.mkDeclaredEdges: element 0, 'from': got string, which was not built by mkNodeRef"
        "gen-graph.mkDeclaredEdges: element 0, 'to': got string, which was not built by mkNodeRef"
      ];
    };
    # Every violating position reports rather than only the first: a validator that stops at one
    # hides the rest of the same defect.
    test-a-list-of-non-ids-is-refused-by-position-and-type = {
      expr = declaredEdgesFindings {
        child = [
          42
          { nope = 1; }
        ];
      };
      expected = [
        "gen-graph.mkDeclaredEdges: key 'child' element 0: got int, which was not built by mkNodeRef"
        "gen-graph.mkDeclaredEdges: key 'child' element 1: got set, which was not built by mkNodeRef"
      ];
    };
    test-an-element-missing-an-endpoint-is-refused-by-name = {
      expr = declaredEdgesFindings [ { from = ref "child"; } ];
      expected = [
        "gen-graph.mkDeclaredEdges: element 0: no 'to' field; expected { from = <node reference>; to = <node reference>; }"
      ];
    };
    # The refusals are throws at the constructor, in both forms, and they fire at CONSTRUCTION.
    test-control-the-bare-string-refusal-really-throws = {
      expr = refusedAtConstruction (mkDeclaredEdges bareStringEndpoint);
      expected = true;
    };
    test-control-a-well-formed-relation-has-no-findings = {
      expr = declaredEdgesFindings attrsetForm;
      expected = [ ];
    };
    # Extra fields are admitted and ignored — the latitude is stated rather than left unwritten.
    test-extra-fields-on-an-element-are-admitted-and-ignored = {
      expr = (mkDeclaredEdges extraFieldForm).dependencies "child";
      expected = [ "parent" ];
    };

    # ── THE CALLABLE FORMS ARE REFUSED BY THE ACCEPT-LIST, NOT BY A DENY ──
    test-a-lambda-relation-is-refused-by-name = {
      expr = declaredEdgesFindings lambdaRelation;
      expected = [
        "gen-graph.mkDeclaredEdges: got lambda, expected either a list of { from = <node reference>; to = <node reference>; } edges or an attrset from a node's canonical name to a list of node references"
      ];
    };
    # THE NORMATIVE ONE. A `__functor` attrset IS the edge set being a function, and it is refused
    # here as a value that is not a list — by the conjunct it must satisfy, not by a roster.
    test-a-functor-relation-is-refused-by-name = {
      expr = declaredEdgesFindings functorRelation;
      expected = [
        "gen-graph.mkDeclaredEdges: key '__functor': got lambda, expected a list of node references"
      ];
    };
    # The seed: the deny-list an implementer reaches for. It is BLIND to the functor form, which is
    # what makes an accept-list the mechanism rather than a preference.
    test-seed-isFunction-cannot-see-the-functor-form = {
      expr = builtins.isFunction functorRelation;
      expected = false;
    };
    test-control-isFunction-does-see-the-plain-lambda = {
      expr = builtins.isFunction lambdaRelation;
      expected = true;
    };

    # ── THE FORCE DEPTH IS `deepSeq`, ASSERTED BY ITS OBSERVABLE CONSEQUENCE ──
    # There is no cell for the knot itself: under the deep force it is `infinite recursion
    # encountered`, which escapes `tryEval` and would kill the suite rather than fail a cell. What is
    # assertable is the depth that causes it.
    test-a-throw-in-an-extra-field-fires-at-construction = {
      expr = refusedAtConstruction (mkDeclaredEdges depthSeedExtraField);
      expected = true;
    };
    test-a-throw-below-the-tag-check-fires-at-construction = {
      expr = refusedAtConstruction (mkDeclaredEdges depthSeedRefId);
      expected = true;
    };
    # Both seeds pass a WHNF force …
    test-seed-whnf-force-admits-the-extra-field-throw = {
      expr = refusedAtConstruction (seedWhnf depthSeedExtraField);
      expected = false;
    };
    test-seed-whnf-force-admits-the-throw-below-the-tag-check = {
      expr = refusedAtConstruction (seedWhnf depthSeedRefId);
      expected = false;
    };
    # … and so does the interposed per-value depth, which is the one a reader cannot see by reading
    # the input type alone.
    test-seed-per-value-force-admits-the-throw-below-the-tag-check = {
      expr = refusedAtConstruction (seedPerValue depthSeedRefId);
      expected = false;
    };
    # THE CONTROL THAT MAKES THE TRIPLE A DEPTH MEASUREMENT AND NOT A WELL-FORMEDNESS ONE: an honest
    # relation — endpoints obtained from the constructor, never bare strings — constructs under all
    # three depths.
    test-control-an-honest-relation-constructs-under-all-three-depths = {
      expr = map refusedAtConstruction [
        (mkDeclaredEdges listForm)
        (seedWhnf listForm)
        (seedPerValue listForm)
      ];
      expected = [
        false
        false
        false
      ];
    };
    # … and the callable form stays refused under all three, so the weakened force is weakened and
    # not broken.
    test-control-the-functor-form-is-refused-under-all-three-depths = {
      expr = map refusedAtConstruction [
        (mkDeclaredEdges functorRelation)
        (seedWhnf functorRelation)
        (seedPerValue functorRelation)
      ];
      expected = [
        true
        true
        true
      ];
    };

    # ── THE SHARED TYPE · THE BYPASS IS CLOSED NOMINALLY ──
    # A contract enforced only inside the fold that reads the relation is bypassed by any caller who
    # hand-assembles the context, and callers do exactly that.
    test-a-hand-assembled-edge-set-is-not-the-type = {
      expr = isDeclaredEdges handAssembled;
      expected = false;
    };
    test-control-the-constructor-s-output-is-the-type = {
      expr = isDeclaredEdges declared;
      expected = true;
    };
    # The seed: a STRUCTURAL predicate. It admits the hand-assembled bypass, which has the right
    # shape and no tag — the whole reason the type is nominal.
    test-seed-a-structural-predicate-admits-the-bypass = {
      expr = seedShapePredicate handAssembled;
      expected = true;
    };
    # The seed is not simply broken: it agrees with the real predicate on the constructor's output,
    # which is why a suite comparing only the accepted case could not separate them.
    test-control-the-structural-seed-agrees-on-the-real-thing = {
      expr = seedShapePredicate declared;
      expected = true;
    };
    # A raw relation is not the type either — the type is what the CONSTRUCTOR mints, so an entry
    # point accepting one is accepting the contract and not a shape.
    test-a-raw-relation-is-not-the-type = {
      expr = isDeclaredEdges attrsetForm;
      expected = false;
    };
  };
}
