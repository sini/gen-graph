# THE RECORD DOORS (den-hoag-7gp66 P1, spec §v1.2): every published door taking a record composes
# gen-prelude's shared checks, so a missing field, and an unknown one at a closed door, is a throw
# `tryEval` observes rather than Nix's uncatchable arity abort. The message cells live on `testsError`
# (`door-refusals`, `door-naming`); this file holds what an error cell cannot say — that the refusal
# is catchable, that it fires when the RECORD is applied (each cell `seq`s the door applied to the
# record and nothing else: no later argument, no field read), that a record door admits an extra
# field (R5), and that the valid call is unchanged.
{ genGraph, ... }:
let
  F = import ./_fixtures/doors.nix { inherit genGraph; };
  applied = d: r: (builtins.tryEval (builtins.seq (d.door r) true)).success;
  extra = {
    ${F.unknown} = 1;
  };
  each = f: builtins.mapAttrs (_: f);
in
{
  flake.tests.doors = {
    test-the-valid-record-is-admitted-at-every-door = {
      expr = each (d: applied d d.good) (F.records // F.options // F.mixed);
      expected = each (_: true) (F.records // F.options // F.mixed);
    };
    test-a-missing-field-is-refused-catchably = {
      expr = each (d: applied d (builtins.removeAttrs d.good [ d.drop ])) (F.records // F.mixed);
      expected = each (_: false) (F.records // F.mixed);
    };
    test-an-unknown-field-is-refused-catchably-at-a-closed-door = {
      expr = each (d: applied d (d.good // extra)) (F.options // F.mixed);
      expected = each (_: false) (F.options // F.mixed);
    };
    # R5's stated price: a record is open, so the extra field is admitted and never reported.
    test-an-extra-field-is-admitted-at-a-record-door = {
      expr = each (d: applied d (d.good // extra)) F.records;
      expected = each (_: true) F.records;
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
        (genGraph.fixpoint {
          seed = { };
          step = _: { a = [ "b" ]; };
        })
        ((genGraph.mkNodeRef { isRegistered = _: true; }) "a").id
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
