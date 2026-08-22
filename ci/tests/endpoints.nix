# THE ENDPOINT PROJECTION'S ORACLES.
#
# Every cell below names the SEEDED DEFECT it refuses, and each seed is CONSTRUCTED IN THIS FILE and
# evaluated in the same run as the cell that passes clean — a guard whose seed is only described has
# not been shown to discriminate. The seeds are the wrong constructions an implementer plausibly
# reaches for: the un-deduplicated projection, the projection written for one family, the private
# copy of the child-bearing names, the ungated check, and the check gated on a literal name.
#
# WHY THE SEEDS RETURN WRONG VALUES RATHER THAN ABORTING. Reading an attrset as a list, or taking
# `attrNames` of a list, raises a Nix TYPE error rather than a `throw`, and a type error is not
# `tryEval`-catchable: a seed built that way would take its sibling cells down with it instead of
# failing one. Each seed here is therefore built in its SILENT form — the form that returns a
# smaller-but-plausible answer — which is also the form that actually reaches production.
{ genGraph, genPrelude, ... }:
let
  inherit (genGraph)
    mkEndpointProjection
    mkProjectionFindings
    transpose
    materialize
    ;

  didThrow = v: !(builtins.tryEval (builtins.deepSeq v true)).success;
  sorted = builtins.sort builtins.lessThan;

  # ── THE SUBSTRATE'S TWO PREDICATES, AS THE CALLER WOULD SUPPLY THEM ──
  # The evaluated node set is the membership authority, so it carries the SPAWNED node as well as
  # the registered ones. That is the whole point of taking the evaluated set rather than the
  # registration set, and `test-control-spawned-endpoint-is-admitted` is what holds it.
  childBearing = name: name == "children" || name == "derived-children";
  evaluatedNodes = [
    "a"
    "a-spawned"
    "b"
    "c"
    "d"
  ];
  isNode = t: builtins.elem t evaluatedNodes;
  registeredOnly =
    t:
    builtins.elem t [
      "a"
      "b"
      "c"
      "d"
    ];

  authority = { inherit childBearing isNode; };
  projection = mkEndpointProjection authority;
  findings = mkProjectionFindings authority;

  # A structural record built from one node's attributes; every other id is a leaf. Written as a
  # function so a fixture is a record and a projection is that record read.
  recordOf =
    attrs: id:
    if id == "a" then
      attrs
    else
      {
        children = { };
        derived-children = { };
        edges-owns = [ ];
      };

  # ── THE FIXTURES ──
  # Both families present, and each family's two members contributing DIFFERENT targets, so a
  # projection that dropped either family is visible in the value rather than only in its absence.
  mixed = recordOf {
    children = {
      b = {
        id = "b";
      };
    };
    derived-children = {
      a-spawned = {
        id = "a-spawned";
      };
    };
    edges-owns = [ "c" ];
    imports = [ "d" ];
    includes = [ ];
  };

  onlyChildBearing = recordOf {
    children = {
      b = {
        id = "b";
      };
    };
    derived-children = {
      a-spawned = {
        id = "a-spawned";
      };
    };
  };

  onlyListFamily = recordOf {
    edges-owns = [ "c" ];
    imports = [ "d" ];
  };

  # The child record's VALUE is poisoned; its KEY is not. `attrNames` reads keys only.
  poisonedChildRecord = recordOf {
    children = {
      b = throw "gen-graph: the child record's contents were forced";
    };
    edges-owns = [ "c" ];
  };

  # The three violation modes and the two admitting controls, each as its own record so all five
  # can be measured in ONE evaluation.
  violating = value: recordOf { edges-owns = value; };

  # ── THE SEEDS ──
  # (1) The un-deduplicated projection: the definition without its `unique`, which emits a MULTISET.
  seedNoDedup =
    saOf: id:
    let
      sa = saOf id;
    in
    builtins.concatMap (name: if childBearing name then builtins.attrNames sa.${name} else sa.${name}) (
      builtins.attrNames sa
    );

  # (2) The projection written for the child-bearing family alone — the family every reader has in
  # mind. It returns a smaller, entirely plausible endpoint set.
  seedChildBearingOnly =
    saOf: id:
    let
      sa = saOf id;
    in
    genPrelude.unique (
      builtins.concatMap (name: if childBearing name then builtins.attrNames sa.${name} else [ ]) (
        builtins.attrNames sa
      )
    );

  # (3) The mirror of (2): written for the list family alone.
  seedListFamilyOnly =
    saOf: id:
    let
      sa = saOf id;
    in
    genPrelude.unique (
      builtins.concatMap (name: if childBearing name then [ ] else sa.${name}) (builtins.attrNames sa)
    );

  # (4) The `children`-alone read — the defect that makes a spawned node invisible to a structural
  # query. It names a MEMBER of the partition instead of enumerating the partition.
  seedChildrenLiteralRead =
    saOf: id:
    let
      sa = saOf id;
    in
    genPrelude.unique (builtins.attrNames (sa.children or { }));

  # (5) The private copy of the two child-bearing names, held inside the projection instead of
  # taken from the substrate. Identical to the real one until the substrate grows a third name.
  seedPrivateFamilyCopy = mkEndpointProjection {
    childBearing = name: name == "children" || name == "derived-children";
    inherit isNode;
  };

  # (6) The check gated on the LITERAL name `children` rather than on the injected predicate. It
  # governs `derived-children`, which is the non-obvious member of the family it must not govern.
  seedLiteralNameGate = mkEndpointProjection {
    childBearing = name: name == "children";
    inherit isNode;
  };

  # (7) The ungated check — the contract mapped over EVERY structural name. Its answer is identical
  # to the real one on a clean graph, which is exactly why no value-comparing cell can catch it;
  # what catches it is the DOMAIN.
  seedUngatedFindings = mkProjectionFindings {
    childBearing = _: false;
    inherit isNode;
  };

  # The substrate that grew a third child-bearing name, and the projection instantiated against it.
  # No line of the projection changes between this and `projection`.
  grownChildBearing = name: childBearing name || name == "extra-children";
  grownProjection = mkEndpointProjection {
    childBearing = grownChildBearing;
    inherit isNode;
  };
  grownRecord = recordOf {
    children = {
      b = {
        id = "b";
      };
    };
    extra-children = {
      c = {
        id = "c";
      };
    };
  };
in
{
  flake.tests.endpoints = {

    # ── O1 · TOTAL OVER BOTH FAMILIES IN ONE GRAPH ──
    test-o1-both-families-in-one-graph = {
      expr = sorted (projection mixed "a");
      expected = [
        "a-spawned"
        "b"
        "c"
        "d"
      ];
    };
    # The seeds: each family's projection written alone, both silent, both plausible.
    test-o1-seed-child-bearing-only-loses-the-list-family = {
      expr = sorted (seedChildBearingOnly mixed "a");
      expected = [
        "a-spawned"
        "b"
      ];
    };
    test-o1-seed-list-family-only-loses-the-child-bearing-family = {
      expr = sorted (seedListFamilyOnly mixed "a");
      expected = [
        "c"
        "d"
      ];
    };
    # Each family answers correctly IN ISOLATION — without these, a mixed-graph pass could be
    # silently empty on one family and the total still look right.
    test-control-child-bearing-family-alone-answers = {
      expr = sorted (projection onlyChildBearing "a");
      expected = [
        "a-spawned"
        "b"
      ];
    };
    test-control-list-family-alone-answers = {
      expr = sorted (projection onlyListFamily "a");
      expected = [
        "c"
        "d"
      ];
    };

    # ── O2 · THE PROJECTION REACHES SPAWNED NODES ──
    # It enumerates the partition rather than naming a member of it, so a node arriving through the
    # spawn channel is reached by construction.
    test-o2-spawned-node-is-reached = {
      expr = builtins.elem "a-spawned" (projection mixed "a");
      expected = true;
    };
    test-o2-seed-children-alone-cannot-see-the-spawned-node = {
      expr = seedChildrenLiteralRead mixed "a";
      expected = [ "b" ];
    };
    # Both families are present in the answer, so neither stands in for the other …
    test-control-selected-child-is-reached-too = {
      expr = builtins.elem "b" (projection mixed "a");
      expected = true;
    };
    # … and a leaf projects empty, so a non-empty answer is topology rather than ⊤.
    test-control-leaf-projects-empty = {
      expr = projection mixed "b";
      expected = [ ];
    };

    # ── O3 · THE FAMILY RULE IS THE SUBSTRATE'S, NOT A COPY ──
    # A third child-bearing name reaches the projection through the injected predicate, with no
    # edit to the projection.
    test-o3-a-grown-family-rule-changes-the-reading = {
      expr = sorted (grownProjection grownRecord "a");
      expected = [
        "b"
        "c"
      ];
    };
    # The private copy is the seed. It reads the new name as the OTHER family — here that refuses,
    # because the value is an attrset; in a substrate that hands it an unwrapped value it is silent.
    test-o3-seed-private-copy-misreads-the-grown-family = {
      expr = didThrow (seedPrivateFamilyCopy grownRecord "a");
      expected = true;
    };
    # The cell measures the WIRING and not a constant: on a record without the new name, the grown
    # predicate and the shipped one agree exactly.
    test-control-grown-rule-is-inert-without-the-new-name = {
      expr = sorted (grownProjection mixed "a") == sorted (projection mixed "a");
      expected = true;
    };

    # ── O5 · THE DIRECTION IS PARENT → CHILD ──
    # A transposed projection is a one-character-class error that yields a fully populated and
    # entirely plausible relation, so the cell asserts the direction rather than the population.
    test-o5-parent-reaches-child = {
      expr = builtins.elem "b" (projection mixed "a");
      expected = true;
    };
    test-o5-child-does-not-reach-parent = {
      expr = builtins.elem "a" (projection mixed "b");
      expected = false;
    };
    test-o5-seed-transposed-relation-puts-the-parent-under-the-child = {
      expr =
        let
          edgeMap = materialize {
            nodes = evaluatedNodes;
            edges = projection mixed;
          };
          flipped = transpose {
            nodes = evaluatedNodes;
            edges = id: edgeMap.${id} or [ ];
          };
        in
        flipped.edges "b";
      expected = [ "a" ];
    };
    # The transposed relation is POPULATED, which is what makes it plausible — the seed is not
    # caught by anything that only checks the cone is non-empty.
    test-control-transposed-relation-is-non-empty = {
      expr =
        let
          edgeMap = materialize {
            nodes = evaluatedNodes;
            edges = projection mixed;
          };
          flipped = transpose {
            nodes = evaluatedNodes;
            edges = id: edgeMap.${id} or [ ];
          };
        in
        builtins.length (builtins.concatMap flipped.edges evaluatedNodes);
      expected = 4;
    };

    # ── O6 · THE PROJECTION FORCES NO CHILD RECORD'S CONTENTS ──
    # Keys are eager and values are lazy; the child family reads keys.
    test-o6-child-record-contents-are-not-forced = {
      expr = sorted (projection poisonedChildRecord "a");
      expected = [
        "b"
        "c"
      ];
    };
    # The poison really throws when the record is read directly — without this the cell passes
    # against a poison that never fired.
    test-control-the-poisoned-child-record-really-throws = {
      expr = didThrow (poisonedChildRecord "a").children.b;
      expected = true;
    };

    # ── O8 · THE CODOMAIN IS REFUSED WHEN VIOLATED, ON BOTH HALVES ──
    # All four modes return in ONE evaluation: the refusals are `throw`s, never coercion aborts.
    test-o8-non-list-is-refused = {
      expr = didThrow (projection (violating "not-a-list") "a");
      expected = true;
    };
    test-o8-junk-elements-are-refused = {
      expr = didThrow (
        projection (violating [
          42
          { nope = 1; }
        ]) "a"
      );
      expected = true;
    };
    test-o8-phantom-id-is-refused = {
      expr = didThrow (projection (violating [ "ghost" ]) "a");
      expected = true;
    };
    # The assertion is on the RETURNED MESSAGE, never on a caught throw: a caught throw proves only
    # that something refused, never that it refused for the reason under test.
    test-o8-non-list-message-names-node-family-and-type = {
      expr = findings (violating "not-a-list") "a";
      expected = [
        "gen-graph.mkEndpointProjection: node 'a' structural attribute 'edges-owns': got string, expected a list of node ids"
      ];
    };
    # Every violating element reports, and NEITHER message interpolates its offender — naming a
    # non-string is the coercion abort that would make this very cell unable to fire.
    test-o8-junk-element-messages-name-position-and-type = {
      expr = findings (violating [
        42
        { nope = 1; }
      ]) "a";
      expected = [
        "gen-graph.mkEndpointProjection: node 'a' structural attribute 'edges-owns' element 0: got int, expected a node id"
        "gen-graph.mkEndpointProjection: node 'a' structural attribute 'edges-owns' element 1: got set, expected a node id"
      ];
    };
    # Only the membership refusal names an id, because only there is one known to exist.
    test-o8-phantom-message-names-the-offending-id = {
      expr = findings (violating [ "ghost" ]) "a";
      expected = [
        "gen-graph.mkEndpointProjection: node 'a' structural attribute 'edges-owns': 'ghost' is not a node of the evaluated graph"
      ];
    };
    # A well-formed attribute projects its references …
    test-control-well-formed-attribute-is-admitted = {
      expr = projection (violating [ "b" ]) "a";
      expected = [ "b" ];
    };
    test-control-well-formed-attribute-has-no-findings = {
      expr = findings (violating [ "b" ]) "a";
      expected = [ ];
    };
    # … and ★ AN EMPTY ONE IS ADMITTED. Without this control the cell passes a check that refuses
    # every list, which is a refuse-everything guard wearing a contract's name.
    test-control-empty-attribute-is-admitted = {
      expr = projection (violating [ ]) "a";
      expected = [ ];
    };
    test-control-empty-attribute-has-no-findings = {
      expr = findings (violating [ ]) "a";
      expected = [ ];
    };

    # ── O9 · A PHANTOM ENDPOINT IS REFUSED, AND A SPAWNED ONE IS NOT ──
    test-o9-typo-id-is-refused = {
      expr = didThrow (projection (violating [ "ghost" ]) "a");
      expected = true;
    };
    # ★ THE CONTROL THAT MATTERS MOST. The membership authority is the EVALUATED set, never the
    # registration set — wrongly refusing every product of the spawn channel is the likelier
    # implementation error than admitting a phantom.
    test-control-spawned-endpoint-is-admitted = {
      expr = projection (violating [ "a-spawned" ]) "a";
      expected = [ "a-spawned" ];
    };
    # The seed: the registration set as the authority. It refuses the spawned node, and its refusal
    # is indistinguishable from a correct one unless the control above is present.
    test-o9-seed-registration-set-authority-refuses-the-spawned-node = {
      expr = didThrow (
        mkEndpointProjection {
          inherit childBearing;
          isNode = registeredOnly;
        } (violating [ "a-spawned" ]) "a"
      );
      expected = true;
    };

    # ── O10 · THE PROJECTION EMITS A SET ──
    # (a) THE NON-OBVIOUS MEMBER, and the one that anchors the cell: the same target under TWO
    # LABELS. An author reading "one edge per label" does not see a duplicate coming.
    test-o10-two-labels-one-target-emit-one-element = {
      expr = projection (recordOf {
        edges-owns = [ "b" ];
        edges-uses = [ "b" ];
      }) "a";
      expected = [ "b" ];
    };
    test-o10-seed-undeduplicated-two-labels-emit-a-multiset = {
      expr = seedNoDedup (recordOf {
        edges-owns = [ "b" ];
        edges-uses = [ "b" ];
      }) "a";
      expected = [
        "b"
        "b"
      ];
    };
    # (b) The obvious member, and a wholly ordinary graph shape: a child that is also a target.
    test-o10-child-that-is-also-a-target-emits-one-element = {
      expr = projection (recordOf {
        children = {
          b = {
            id = "b";
          };
        };
        imports = [ "b" ];
      }) "a";
      expected = [ "b" ];
    };
    test-o10-seed-undeduplicated-child-and-target-emit-a-multiset = {
      expr = seedNoDedup (recordOf {
        children = {
          b = {
            id = "b";
          };
        };
        imports = [ "b" ];
      }) "a";
      expected = [
        "b"
        "b"
      ];
    };
    # ★ THE CONTROL THAT MAKES THIS A DUPLICATE TEST RATHER THAN A LENGTH TEST: distinct targets in
    # the same two-label shape survive. Without it, a projection dropping every second element
    # would pass every cell above.
    test-control-distinct-targets-under-two-labels-both-survive = {
      expr = sorted (
        projection (recordOf {
          edges-owns = [ "b" ];
          edges-uses = [ "c" ];
        }) "a"
      );
      expected = [
        "b"
        "c"
      ];
    };

    # ── O12 · THE CHECK'S DOMAIN IS THE GOVERNED FAMILY AND ONLY IT ──
    # Measured directly rather than inferred from a value: with an authority that admits NOTHING,
    # every name the check touches produces a finding that names it. What comes back is the domain.
    test-o12-the-checked-names-are-exactly-the-non-child-bearing-ones = {
      expr =
        mkProjectionFindings {
          inherit childBearing;
          isNode = _: false;
        } onlyChildBearing "a"
        ++ mkProjectionFindings {
          inherit childBearing;
          isNode = _: false;
        } (recordOf { edges-owns = [ "b" ]; }) "a";
      expected = [
        "gen-graph.mkEndpointProjection: node 'a' structural attribute 'edges-owns': 'b' is not a node of the evaluated graph"
      ];
    };
    # ★ `derived-children` MUST BE EXCLUDED — the NON-OBVIOUS member, and it anchors the cell.
    # `children` is the one every reader thinks of, so a cell testing only `children` passes an
    # implementation gated on that literal name.
    test-control-derived-children-is-outside-the-domain = {
      expr = projection (recordOf {
        derived-children = {
          a-spawned = {
            id = "a-spawned";
          };
        };
        edges-owns = [ "b" ];
      }) "a";
      expected = [
        "a-spawned"
        "b"
      ];
    };
    test-o12-seed-literal-name-gate-refuses-derived-children = {
      expr = didThrow (
        seedLiteralNameGate (recordOf {
          derived-children = {
            a-spawned = {
              id = "a-spawned";
            };
          };
          edges-owns = [ "b" ];
        }) "a"
      );
      expected = true;
    };
    test-control-children-is-outside-the-domain = {
      expr = projection (recordOf {
        children = {
          b = {
            id = "b";
          };
        };
        edges-owns = [ "c" ];
      }) "a";
      expected = [
        "b"
        "c"
      ];
    };
    # ★ THE INCLUDE DIRECTION. Without it the cell passes a check that is applied to nothing at all.
    test-control-a-governed-name-is-inside-the-domain = {
      expr = didThrow (projection (violating [ "ghost" ]) "a");
      expected = true;
    };
    # The ungated seed's ANSWER on a clean graph is identical to the real one, which is why the
    # domain rather than the value is what catches it.
    test-o12-seed-ungated-check-governs-the-child-bearing-family = {
      expr = builtins.length (
        seedUngatedFindings (recordOf {
          children = {
            b = {
              id = "b";
            };
          };
          derived-children = {
            a-spawned = {
              id = "a-spawned";
            };
          };
          edges-owns = [ "b" ];
        }) "a"
      );
      expected = 2;
    };
  };
}
