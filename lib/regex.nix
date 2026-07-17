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

  # ── string sugar ──────────────────────────────────────────────────────────
  # grammar:  expr := seqE ("|" seqE)*        (alternation binds loosest)
  #           seqE := post+                    (juxtaposition = sequence)
  #           post := atom ("*" | "?" | "+")?
  #           atom := LABEL | "_" | "(" expr ")"
  # LABEL chars: [A-Za-z0-9_-] — but a lone "_" is the any-label wildcard.
  # Character-level tokenizer + recursive-descent over the token list; index
  # threaded, no regex builtins (builtins.match over user strings backtracks and
  # can stack-overflow — see REFERENCE.md).
  parse =
    s:
    let
      err = m: throw "gen-graph.regex.parse: ${m} (in ${builtins.toJSON s})";
      n = builtins.stringLength s;
      isLabelChar =
        c:
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_" || c == "-";
      # tokenize → [ { t = "label"|"("|")"|"|"|"*"|"?"|"+"; v? } ]
      tokenize =
        i:
        if i >= n then
          [ ]
        else
          let
            c = builtins.substring i 1 s;
          in
          if c == " " || c == "\t" || c == "\n" then
            tokenize (i + 1)
          else if c == "(" || c == ")" || c == "|" || c == "*" || c == "?" || c == "+" then
            [ { t = c; } ] ++ tokenize (i + 1)
          else if isLabelChar c then
            let
              takeEnd = j: if j < n && isLabelChar (builtins.substring j 1 s) then takeEnd (j + 1) else j;
              e = takeEnd i;
            in
            [
              {
                t = "label";
                v = builtins.substring i (e - i) s;
              }
            ]
            ++ tokenize e
          else
            err "unexpected character '${c}'";
      toks = tokenize 0;
      len = builtins.length toks;
      at = i: builtins.elemAt toks i;

      # each parser: i → { re; i; }
      pAtom =
        i:
        if i >= len then
          err "unexpected end of input"
        else
          let
            tok = at i;
          in
          if tok.t == "label" then
            {
              re = if tok.v == "_" then any else lit tok.v;
              i = i + 1;
            }
          else if tok.t == "(" then
            let
              inner = pExpr (i + 1);
            in
            if inner.i < len && (at inner.i).t == ")" then
              {
                re = inner.re;
                i = inner.i + 1;
              }
            else
              err "unbalanced parenthesis"
          else
            err "unexpected token '${tok.t}'";
      pPost =
        i:
        let
          a = pAtom i;
          tok = if a.i < len then (at a.i).t else "";
        in
        if tok == "*" then
          {
            re = star a.re;
            i = a.i + 1;
          }
        else if tok == "?" then
          {
            re = opt a.re;
            i = a.i + 1;
          }
        else if tok == "+" then
          {
            re = plus a.re;
            i = a.i + 1;
          }
        else
          a;
      startsAtom = i: i < len && ((at i).t == "label" || (at i).t == "(");
      pSeq =
        i:
        let
          go =
            acc: j:
            if startsAtom j then
              let
                p = pPost j;
              in
              go (acc ++ [ p.re ]) p.i
            else
              {
                re = seq acc;
                i = j;
              };
        in
        if startsAtom i then go [ ] i else err "expected a label or '('";
      pExpr =
        i:
        let
          first = pSeq i;
          go =
            acc: j:
            if j < len && (at j).t == "|" then
              let
                nxt = pSeq (j + 1);
              in
              go (acc ++ [ nxt.re ]) nxt.i
            else
              {
                re = alt acc;
                i = j;
              };
        in
        go [ first.re ] first.i;
      result =
        if toks == [ ] then
          {
            re = eps;
            i = 0;
          }
        else
          pExpr 0;
    in
    if result.i == len then result.re else err "trailing tokens";
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
    parse
    ;
}
