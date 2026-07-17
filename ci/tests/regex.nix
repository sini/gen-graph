{ genGraph, ... }:
let
  inherit (genGraph) regex;
  r = regex;
  # acceptance oracle: fold derivatives over a word, check nullability
  accepts = re: word: r.nullable (builtins.foldl' (st: l: r.deriv l st) re word);
in
{
  flake.tests.regex = {
    test-lit-accepts-itself = {
      expr = accepts (r.lit "a") [ "a" ];
      expected = true;
    };
    test-lit-rejects-other = {
      expr = accepts (r.lit "a") [ "b" ];
      expected = false;
    };
    test-eps-accepts-empty = {
      expr = accepts r.eps [ ];
      expected = true;
    };
    test-empty-rejects-empty = {
      expr = accepts r.empty [ ];
      expected = false;
    };
    test-seq-order = {
      expr =
        accepts
          (r.seq [
            (r.lit "a")
            (r.lit "b")
          ])
          [
            "a"
            "b"
          ];
      expected = true;
    };
    test-seq-wrong-order = {
      expr =
        accepts
          (r.seq [
            (r.lit "a")
            (r.lit "b")
          ])
          [
            "b"
            "a"
          ];
      expected = false;
    };
    test-star-empty = {
      expr = accepts (r.star (r.lit "a")) [ ];
      expected = true;
    };
    test-star-many = {
      expr = accepts (r.star (r.lit "a")) [
        "a"
        "a"
        "a"
      ];
      expected = true;
    };
    test-star-then-lit = {
      expr =
        accepts
          (r.seq [
            (r.star (r.lit "c"))
            (r.lit "n")
          ])
          [
            "c"
            "c"
            "n"
          ];
      expected = true;
    };
    test-opt-present = {
      expr =
        accepts
          (r.seq [
            (r.lit "a")
            (r.opt (r.lit "b"))
          ])
          [
            "a"
            "b"
          ];
      expected = true;
    };
    test-opt-absent = {
      expr = accepts (r.seq [
        (r.lit "a")
        (r.opt (r.lit "b"))
      ]) [ "a" ];
      expected = true;
    };
    test-plus-zero-rejected = {
      expr = accepts (r.plus (r.lit "a")) [ ];
      expected = false;
    };
    test-alt-either = {
      expr = accepts (r.alt [
        (r.lit "a")
        (r.lit "b")
      ]) [ "b" ];
      expected = true;
    };
    test-any-single = {
      expr = accepts r.any [ "whatever" ];
      expected = true;
    };
    test-star-any-universal = {
      expr = accepts (r.star r.any) [
        "x"
        "y"
        "z"
      ];
      expected = true;
    };

    # ACI canonicalization (Owens–Reppy–Turon: finitely many derivatives modulo ACI)
    test-alt-commutes = {
      expr =
        r.stateKey (
          r.alt [
            (r.lit "a")
            (r.lit "b")
          ]
        ) == r.stateKey (
          r.alt [
            (r.lit "b")
            (r.lit "a")
          ]
        );
      expected = true;
    };
    test-alt-idempotent = {
      expr =
        r.stateKey (
          r.alt [
            (r.lit "a")
            (r.lit "a")
          ]
        ) == r.stateKey (r.lit "a");
      expected = true;
    };
    test-star-star-collapses = {
      expr = r.stateKey (r.star (r.star (r.lit "a"))) == r.stateKey (r.star (r.lit "a"));
      expected = true;
    };
    test-seq-empty-absorbs = {
      expr =
        r.stateKey (
          r.seq [
            (r.lit "a")
            r.empty
          ]
        ) == r.stateKey r.empty;
      expected = true;
    };
    test-seq-eps-drops = {
      expr =
        r.stateKey (
          r.seq [
            r.eps
            (r.lit "a")
          ]
        ) == r.stateKey (r.lit "a");
      expected = true;
    };

    # finiteness: derivative closure of a star-alt reaches a fixed keyset (bounded)
    test-derivative-space-finite = {
      expr =
        let
          re0 = r.seq [
            (r.star (
              r.alt [
                (r.lit "c")
                (r.lit "i")
              ]
            ))
            (r.opt (r.lit "n"))
          ];
          labels = [
            "c"
            "i"
            "n"
          ];
          step =
            states:
            let
              next = builtins.foldl' (
                acc: st: builtins.foldl' (a: l: a // { ${r.stateKey (r.deriv l st)} = r.deriv l st; }) acc labels
              ) states (builtins.attrValues states);
            in
            if builtins.attrNames next == builtins.attrNames states then states else step next;
          all = step { ${r.stateKey re0} = re0; };
        in
        builtins.length (builtins.attrNames all) < 12;
      expected = true;
    };
  };
}
