# Label-regex kernel for graph queries: Brzozowski (1964) derivatives with the
# ACI normalization of Owens, Reppy & Turon (2009) — alternation is flattened,
# sorted and deduplicated, sequence is flattened with unit/zero absorption, and
# star is collapsed, so the set of derivatives of any expression is finite and
# `stateKey` is a canonical seen-set key. Labels are the edge-kind names of a
# labeled graph (Néron et al. 2015); a query's path constraint is a word in
# this alphabet. Labels are expected to match [A-Za-z0-9_-]+ (the parse
# alphabet): a label containing rendering metacharacters (* | . parens) can
# collide with a composite's canonical rendering in stateKey — constructor
# callers own this constraint (see README).
{ prelude }:
let
  # ── constructors normalize on the way in ─────────────────────────────────
  eps = {
    t = "eps";
  };
  empty = {
    t = "empty";
  };
  any = {
    t = "any";
  };
  lit = l: {
    t = "lit";
    inherit l;
  };

  isT = t: r: r.t == t;

  # canonical rendering; alt is sorted by this, making it a true canonical form
  stateKey =
    r:
    if r.t == "eps" then
      "e"
    else if r.t == "empty" then
      "0"
    else if r.t == "any" then
      "_"
    else if r.t == "lit" then
      "'" + r.l
    else if r.t == "star" then
      stateKey r.r + "*"
    else if r.t == "seq" then
      "(" + builtins.concatStringsSep "." (map stateKey r.rs) + ")"
    else
      "(" + builtins.concatStringsSep "|" (map stateKey r.rs) + ")";

  seq =
    rs:
    let
      flat = builtins.concatMap (r: if isT "seq" r then r.rs else [ r ]) rs;
      noEps = builtins.filter (r: !(isT "eps" r)) flat;
    in
    if builtins.any (isT "empty") noEps then
      empty
    else if noEps == [ ] then
      eps
    else if builtins.length noEps == 1 then
      builtins.head noEps
    else
      {
        t = "seq";
        rs = noEps;
      };

  alt =
    rs:
    let
      flat = builtins.concatMap (r: if isT "alt" r then r.rs else [ r ]) rs;
      noEmpty = builtins.filter (r: !(isT "empty" r)) flat;
      # dedup + sort by canonical key (ACI: assoc by flatten, comm by sort, idem by dedup)
      byKey = builtins.listToAttrs (
        map (r: {
          name = stateKey r;
          value = r;
        }) noEmpty
      );
      canon = map (k: byKey.${k}) (builtins.sort builtins.lessThan (builtins.attrNames byKey));
    in
    if canon == [ ] then
      empty
    else if builtins.length canon == 1 then
      builtins.head canon
    else
      {
        t = "alt";
        rs = canon;
      };

  star =
    r:
    if isT "star" r then
      r
    else if isT "eps" r || isT "empty" r then
      eps
    else
      {
        t = "star";
        inherit r;
      };

  opt =
    r:
    alt [
      eps
      r
    ];
  plus =
    r:
    seq [
      r
      (star r)
    ];

  nullable =
    r:
    if r.t == "eps" || r.t == "star" then
      true
    else if r.t == "lit" || r.t == "any" || r.t == "empty" then
      false
    else if r.t == "seq" then
      builtins.all nullable r.rs
    else
      builtins.any nullable r.rs;

  # Brzozowski derivative with respect to one label
  deriv =
    l: r:
    if r.t == "eps" || r.t == "empty" then
      empty
    else if r.t == "any" then
      eps
    else if r.t == "lit" then
      (if r.l == l then eps else empty)
    else if r.t == "star" then
      seq [
        (deriv l r.r)
        r
      ]
    else if r.t == "alt" then
      alt (map (deriv l) r.rs)
    else
      # seq: d(r1 r2…) = (d r1) r2… | [r1 nullable] d(r2…)
      let
        hd = builtins.head r.rs;
        tl = builtins.tail r.rs;
        first = seq ([ (deriv l hd) ] ++ tl);
      in
      if nullable hd then
        alt [
          first
          (deriv l (seq tl))
        ]
      else
        first;
in
{
  inherit
    eps
    empty
    any
    lit
    seq
    alt
    star
    opt
    plus
    nullable
    deriv
    stateKey
    ;
}
