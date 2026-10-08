# THE DOORS (den-hoag-7gp66 P1, then P2 — `prelude.door`): every published step taking a record is
# a door, so a missing field, and an unknown one at a closed step, is a throw `tryEval` observes
# rather than Nix's uncatchable arity abort. The message cells live on `testsError` (`door-refusals`,
# `door-naming`); this file holds what an error cell cannot say — that the refusal is catchable,
# that it fires when the STEP is applied (each cell `seq`s the step applied to its argument and
# nothing else: no later argument, no field read), that a record step admits an extra field (R5)
# unless the field is one of its options step's own names (`optionsStep`, G10), that the published
# contract is the row (D3), and that the valid call is unchanged.
{ genGraph, genPrelude, ... }:
let
  F = import ./_fixtures/doors.nix { inherit genGraph; };
  applied = step: r: (builtins.tryEval (builtins.seq (step r) true)).success;
  extra = {
    ${F.unknown} = 1;
  };
  each = f: builtins.mapAttrs (_: f);

  # ── THE CHAINED DOORS, ENUMERATED FROM THE SURFACE (G10, P6) ──
  # Every options door the library publishes (depth <= 2; closed, nothing required), read off its
  # `__contract` rather than a hand list, so a new one is seen whether or not a row was written.
  isDoor = v: builtins.isAttrs v && v ? __contract && v ? __functor;
  surfaceDoors =
    prefix: set:
    builtins.concatMap (
      k:
      let
        p = if prefix == "" then k else "${prefix}.${k}";
        r = builtins.tryEval set.${k};
      in
      if !r.success then
        [ ]
      else if isDoor r.value then
        [
          {
            name = p;
            value = r.value;
          }
        ]
      else if prefix == "" && builtins.isAttrs r.value && !(r.value ? __functor) then
        surfaceDoors p r.value
      else
        [ ]
    ) (builtins.attrNames set);
  optionDoors = builtins.listToAttrs (
    builtins.filter (d: !d.value.__contract.open && d.value.__contract.required == [ ]) (
      surfaceDoors "" genGraph
    )
  );
  # Derived: the options step applied to `{ }` is an open record door.
  chainedAtOnce = builtins.filter (
    n:
    let
      s = builtins.tryEval (optionDoors.${n} { });
    in
    s.success && isDoor s.value && s.value.__contract.open
  ) (builtins.attrNames optionDoors);
  # Every chained door: the derived ones, and each fixture row pairing an options step with a record
  # step further along (`closureOf` is not a surface name).
  chained = builtins.filter (n: builtins.elem n chainedAtOnce || F.records ? ${n}) (
    builtins.attrNames (optionDoors // F.options)
  );
  optionsOf = n: (optionDoors.${n} or F.options.${n}.door).__contract.optional;
  # The record step a published nest reaches, past its positional nodes (den-hoag-ak8va).
  recordNext = c: if c != null && c ? positional then recordNext c.next else c;
  flag =
    v: names:
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = v;
      }) names
    );
in
{
  flake.tests.doors = {
    test-the-empty-options-are-admitted-at-every-options-step = {
      expr = each (d: applied d.door { }) F.options;
      expected = each (_: true) F.options;
    };
    # G1/G4: refused when the options are applied, before any operand or record.
    test-an-unknown-option-is-refused-catchably-at-every-options-step = {
      expr = each (d: applied d.door extra) F.options;
      expected = each (_: false) F.options;
    };
    # D3: the contract is published as data, and the functor-aware reader reads the same map.
    test-every-options-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.door.__contract) optional required open;
        functionArgs = genPrelude.functionArgs d.door;
      }) F.options;
      expected = each (d: {
        inherit (d) optional;
        required = [ ];
        open = false;
        functionArgs = flag true d.optional;
      }) F.options;
    };
    test-the-valid-record-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step d.good) F.records;
      expected = each (_: true) F.records;
    };
    # D2
    test-a-missing-field-is-refused-catchably = {
      expr = each (d: applied d.step (builtins.removeAttrs d.good [ d.drop ])) F.records;
      expected = each (_: false) F.records;
    };
    # G2 / R5, and G10-ctl on the guarded rows: a field no step names is admitted.
    test-an-extra-field-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step (d.good // extra)) F.records;
      expected = each (_: true) F.records;
    };
    # G10 over EVERY chained door: each of its options step's own names (from that step's
    # `__contract`), given on the record, is refused. The answer is the names ADMITTED.
    test-every-option-is-refused-at-every-chained-record-step = {
      expr = builtins.listToAttrs (
        map (n: {
          name = n;
          value = builtins.filter (o: applied F.records.${n}.step (F.records.${n}.good // { ${o} = 1; })) (
            optionsOf n
          );
        }) chained
      );
      expected = builtins.listToAttrs (
        map (n: {
          name = n;
          value = [ ];
        }) chained
      );
    };
    # P6: every options door on the surface is classified, a chained one has a `records` row to be
    # guarded on, and none is waved through as `notChained`. `chainedAtOnce` is pinned as the
    # enumerator's live control: a walk that found nothing would leave both lists empty.
    test-every-chained-door-on-the-surface-is-a-guarded-row = {
      expr = {
        unclassified = builtins.filter (n: !(F.records ? ${n}) && !(builtins.elem n F.notChained)) (
          builtins.attrNames optionDoors
        );
        chainedWithoutRow = builtins.filter (n: !(F.records ? ${n})) chainedAtOnce;
        inherit chainedAtOnce;
        chained = builtins.length chained;
      };
      expected = {
        unclassified = [ ];
        chainedWithoutRow = [ ];
        chainedAtOnce = [
          "condensationClosure"
          "dependents"
          "expandPreorder"
          "foldPreorder"
          "foldReach"
          "fromScan"
          "pathsBetween"
          "seededFixpoint"
          "topoOrder"
          "topoOrderKahn"
          "transitiveClosure"
          "transitiveReduction"
        ];
        # the twelve and `closureOf`
        chained = 13;
      };
    };
    # PARITY (den-hoag-ak8va, gate C1; gating): every chained door publishes its record step AS
    # DATA, `__contract.next` (past any positional nodes), and the nest,
    # read without application, equals the contract the record step answers with. `chained` is
    # the surface enumeration above, so a chain added later is covered without a new row.
    test-every-chained-door-publishes-its-record-step-as-next = {
      expr = builtins.listToAttrs (
        map (n: {
          name = n;
          value =
            recordNext ((optionDoors.${n} or F.options.${n}.door).__contract.next or null)
            == F.records.${n}.step.__contract;
        }) chained
      );
      expected = builtins.listToAttrs (
        map (n: {
          name = n;
          value = true;
        }) chained
      );
    };
    test-every-record-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.step.__contract) required open;
        functionArgs = genPrelude.functionArgs d.step;
      }) F.records;
      expected = each (d: {
        inherit (d) required;
        open = true;
        functionArgs = flag false d.required;
      }) F.records;
    };
    test-a-door-reaching-a-primitive-refuses-catchably = {
      expr = [
        (each (r: (builtins.tryEval (builtins.deepSeq (r.run F.bad) true)).success) F.reached)
        (each (r: (builtins.tryEval (builtins.deepSeq (r.run F.badTarget) true)).success) F.reachedByTarget)
      ];
      expected = [
        (each (_: false) F.reached)
        (each (_: false) F.reachedByTarget)
      ];
    };
    # The valid call answers as it did before the check: one answer per door family.
    test-the-checked-doors-answer-unchanged = {
      expr = [
        (genGraph.topoOrder { } {
          nodes = [
            "a"
            "b"
          ];
          edges = id: { a = [ "b" ]; }.${id} or [ ];
        })
        (
          (genGraph.mkGraph {
            edges = [
              {
                from = "a";
                to = "b";
              }
            ];
          }).edges
            "a"
        )
        (genGraph.fixpoint { } (_: { a = [ "b" ]; }) { })
        ((genGraph.mkNodeRef (_: true)) "a").id
      ];
      expected = [
        {
          ok = true;
          order = [
            "b"
            "a"
          ];
        }
        [ "b" ]
        { a = [ "b" ]; }
        "a"
      ];
    };
  };
}
