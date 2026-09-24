# The attribute name a caller-supplied identifier is KEYED under: its text.
#
# A node or scope name reaches this library from its caller, and a name built from a package
# (`baseNameOf pkgs.hello`) is a string WITH store context. Nix refuses such a string as an
# attribute name (listToAttrs, groupBy, genAttrs, `?`, `.${…}`, `//` with an interpolated key,
# removeAttrs), and the refusal escapes `builtins.tryEval`. The library's other identity decisions
# (`==`, `elem`, genericClosure keys) ignore context. So keying the RAW name aborts on a name the
# rest of the library accepts.
#
# The key is the text with context discarded, which is the partition `==` already induces. Key
# FORMATION never replaces the caller's value: a binding keyed here carries the original as its
# value. That is a claim about this file's two bindings, not about every surface. An EDGE MAP
# (`{ from = [ to … ]; }`) holds a source only as an attribute name, so a surface that reads its
# answer off such a map's keys returns the text: `transpose`'s edges, `dependents`, and
# `fbWork`'s representative when the pass that finds it runs backward. Each of those names the
# context-keeping reading beside it.
# This is gen-prelude `unique`'s keying ("Discarding context in the KEY reproduces `==`'s
# partition precisely; returning the original element preserves the caller's context").
#
# THE GUARD IS LOAD-BEARING. `unsafeDiscardStringContext` COERCES: an `outPath` attrset becomes
# its string and a path is copied to the store. Unguarded, a forged non-string identifier would be
# admitted silently as a key. A non-string passes through unchanged, so it meets exactly the
# TypeError it met before this binding existed.
let
  # `hasContext` first: on a context-free name the discard is the identity, so skipping it spares
  # the string copy it would make on the path every existing caller is on.
  attrKey =
    k:
    if builtins.isString k && builtins.hasContext k then builtins.unsafeDiscardStringContext k else k;

  # ── THE IDENTIFIER REFUSAL, WRITTEN ONCE FOR EVERY DOOR THAT TAKES A NODE ID ──
  # Names the type and never the value: the value is not a string, and interpolating it is the
  # coercion abort the refusal exists to replace. `typeOf` is total, so the message cannot itself
  # abort. A door `seq`s its guard ahead of its body, because a body that only compares the id with
  # `==` never forces it into a type error and would answer a plausible wrong value instead
  # (ADR-0025 item 1: a value or a named refusal, never an interpreter error).
  notAnIdentifier =
    who: v: "gen-graph.${who}: got ${builtins.typeOf v}, expected a node identifier (a string)";

  # For a door whose body keys, indexes or `attrKey`s the id: only a string is a node id there.
  identifier = who: v: if builtins.isString v then v else throw (notAnIdentifier who v);

  # For a door whose body only hands the id to the caller's accessor and to `genericClosure`/`==`:
  # that body answers correctly on an integer id today, so the guard refuses only the shapes that
  # are never a node id (den-hoag-bkdkg C1), and keeps every scalar the caller's accessor keys on.
  # Callable is a function, or a set whose `__functor` is one: `f ? __functor` alone admits
  # `{ __functor = 1; }`, which aborts when applied. gen-view's `callable` (`lib/relation.nix`).
  # A per-application site tests `builtins.isFunction` inline first, so a plain function costs no call.
  callable =
    v:
    builtins.isFunction v || (builtins.isAttrs v && v ? __functor && builtins.isFunction v.__functor);

  # The id is rendered only when it is a string: a refusal that coerced a caller value into its own
  # message would abort in the act of refusing.
  renderId = id: if builtins.isString id then builtins.toJSON id else "<a ${builtins.typeOf id}>";

  # ── ANY OTHER CALLER FUNCTION (den-hoag-pqp4z, widened by den-hoag-hekcx) ──
  # `callableAt` is the door: it returns the function or refuses a non-callable by name. A surface
  # binds its result in a `let`, so the door is forced by the first application and never again.
  # `badResult` is the refusal a site throws when an applied result is not the type it reads; the
  # test itself is written out at the site. Both name the type and never the value. A function the
  # library applies one argument at a time has its first result tested at the site too, with
  # `builtins.isFunction h || callable h`, before the second application.
  callableAt =
    surface: name: want: f:
    if callable f then
      f
    else
      throw "gen-graph.${surface}: ${name} is a ${builtins.typeOf f}, not a function returning ${want}";
  badResult =
    surface: name: subject: want: v:
    throw "gen-graph.${surface}: ${name} ${subject} returned a ${builtins.typeOf v}, not ${want}";

  # ── THE PLAIN ACCESSOR'S RESULT IS A CLAIM TOO (den-hoag-0mqv1) ──
  # A surface taking `{ edges, ... }` applies `edges` and reads its result as a list. Callability is
  # decided once per invocation, where the first application forces it (`edgesAccessor`); the
  # result is tested for being a list at each application, written out at the site, because a call
  # costs an Env and these sites run once per visit. Only list-ness is checked: what a target must
  # be differs by site, and is not this check's to decide.
  edgesAccessor =
    who: f:
    if builtins.isFunction f || callable f then
      f
    else
      throw "gen-graph.${who}: the accessor's edges is a ${builtins.typeOf f}, not a function from a node id to a list of node ids";
  notEdgeList =
    who: id: v:
    "gen-graph.${who}: edges ${renderId id} returned a ${builtins.typeOf v}, not a list of node ids";

  # A RETIRED argument is still accepted and refused by name (ADR-0025 item 1): dropping it from
  # closed formals would meet a stale caller with an uncatchable `unexpected argument`, and
  # ignoring it would leave a door that describes nothing. `preorder.nix`'s header says why the
  # walks no longer have the ceiling `maxDepth` capped.
  retiredMaxDepth =
    who:
    "gen-graph.${who}: maxDepth is retired. This walk is a builtins.genericClosure loop, not a recursion, so it has no depth ceiling for a cap to sit below; remove the argument.";

  nodeKey =
    who: v:
    if builtins.isAttrs v || builtins.isList v || builtins.isFunction v || v == null then
      throw "gen-graph.${who}: got ${builtins.typeOf v}, expected a node identifier (a string or another scalar)"
    else
      v;
in
{
  inherit
    attrKey
    callable
    callableAt
    badResult
    renderId
    edgesAccessor
    notEdgeList
    retiredMaxDepth
    notAnIdentifier
    identifier
    nodeKey
    ;
  # `genAttrs`, keyed by text: `f` receives the caller's ORIGINAL name, never the key. The guard is
  # written out rather than called: this body runs once per key formed, and a call costs an Env.
  keyedAttrs =
    names: f:
    builtins.listToAttrs (
      map (n: {
        name =
          if builtins.isString n && builtins.hasContext n then builtins.unsafeDiscardStringContext n else n;
        value = f n;
      }) names
    );
}
