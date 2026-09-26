# ── THE CONSTRUCTION FAMILY REFUSES MALFORMED CALLER DATA BY NAME (den-hoag-ndte) ───────────────
# `mkGraph`, `fromScan`, `fromRegistry`, `labeledFrom`, `field` and `fields` read caller data, and
# a read that met the wrong shape aborted past `tryEval`. Each read is guarded where it already
# was (`lib/registry.nix`), so every malformed construction refuses catchably, and a read that
# never met the defect answers exactly as before. The constructions are
# `_fixtures/construction.nix`; the messages are pinned on `testsError` (`ci/tests-error.nix`,
# `construction`).
{ genGraph, ... }:
let
  inherit (import ./_fixtures/construction.nix { inherit genGraph; })
    refusals
    domain
    unkeyed
    ;
  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  materialized =
    g:
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = {
          e = g.edges n;
          p = g.parent n;
          d = g.nodeData n;
        };
      }) g.nodes
    );
in
{
  flake.tests.construction = {
    test-every-malformed-construction-refuses-catchably = {
      expr = builtins.filter (k: admitted refusals.${k}.bad) (builtins.attrNames refusals);
      expected = [ ];
    };
    test-every-well-formed-twin-answers = {
      expr = builtins.filter (k: !admitted refusals.${k}.good) (builtins.attrNames refusals);
      expected = [ ];
    };

    test-an-edge-from-is-not-read-by-parent = {
      expr = domain.edges-from-int-read-through-parent;
      expected = null;
    };
    test-an-item-with-no-reference-keys-no-id = {
      expr = domain.scan-int-id-with-no-reference;
      expected = [ ];
    };
    test-a-scan-that-ignores-its-argument-never-reads-value = {
      expr = domain.scan-ignores-a-missing-value;
      expected = [
        "a"
        "b"
      ];
    };

    # 3w9e7-dependent: re-pin when den-hoag-3w9e7 rules what a node id is
    test-3w9e7-mkGraph-edges-pass-an-int-target-through = {
      expr = unkeyed.mkGraph-edges-to-int;
      expected = [ 42 ];
    };
    test-3w9e7-mkGraph-parent-passes-an-int-through = {
      expr = unkeyed.mkGraph-parents-to-int;
      expected = 42;
    };
    test-3w9e7-fromScan-derived-edges-carry-the-id-as-read = {
      expr = unkeyed.fromScan-derived-from-int;
      expected = [ 42 ];
    };
    test-3w9e7-fromRegistry-edges-pass-an-int-target-through = {
      expr = unkeyed.fromRegistry-target-int;
      expected = [ 42 ];
    };

    # every shipped fixture, every node's edges, parent and data: the digest of the tree before
    # the guards (gen-graph ead9ba8), 1035 bytes of JSON
    test-the-fixtures-materialize-unchanged = {
      expr = builtins.hashString "sha256" (
        builtins.toJSON (builtins.mapAttrs (_: materialized) genGraph.fixtures)
      );
      expected = "40b8d621b4f4dd139f714e59a011bdded7c16ffd42fd21d56393e3fb0ce8a982";
    };
  };
}
