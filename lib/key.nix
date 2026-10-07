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
# admitted silently as a key.
#
# A NON-STRING IS REFUSED HERE, BY THE DOOR'S NAME (den-hoag-2m5iy). Nix refuses every non-string
# as an attribute name (int, bool, float, null, path, a set, an `outPath` set), and that refusal
# escapes `builtins.tryEval`. The throw sits in the thunk the keying operation forces, so it refuses
# exactly the values that operation would abort on, at the same point, and adds no check at any read
# that does not key (ADR-0025 item 1: a value or a named refusal). The one attribute-name form that
# admits a non-string is `{ ${null} = …; }`, which DROPS the binding; a former fed by caller data
# refuses that null instead of losing it. "(a string)" is `identifier`'s rule, and den-hoag-7gp66
# OQ13 ruled it the answer for a node id everywhere (arm a, 2026-09-26): the `genericClosure`
# doors (`reachableFrom`, `reachableWhere`, `canReach`, `coScc`, `selfReachable`, `reachableVia`,
# `selfReachableVia`, `fromRegistryDown`) route their targets through `identifier` now, not
# `nodeKey`. `nodeKey` itself is UNCHANGED and still admits int/bool/float — it is the entry guard
# for a door whose closure keys on `builtins.toJSON […]` rather than on the raw id, so a scalar there
# never reaches `genericClosure`'s native comparator and the type-heterogeneity abort this ruling
# closes does not arise for it (den-hoag-3w9e7's rescope).
#
# `who` is the door the caller invoked. A door binds its former once, `toKey = attrKey who;`, so a
# key formed costs one application, as it did before the refusal existed.
#
# ★ A SHARED PRIMITIVE REACHED THROUGH ANOTHER DOOR REFUSES UNDER THAT DOOR'S NAME (R6, den-hoag-7gp66):
# the door passes `within door prim` where the primitive takes its `who`, and the refusal reads
# `<prefix>.<door>: … (in <prim>)` — the caller is told the door they called, and where it failed.
# Every refusal below renders `who` through `say`, which is the identity on a plain door name.
#
# `prefix` is the library name every refusal below is rendered under (den-hoag-gayc U1a). gen-graph's
# own callers apply this file with `"gen-graph"`; a published copy of this same module, reached over
# `published.key`, lets another library (gen-scope, den-hoag-gayc U1b) apply it with its own name. It
# is one shared module bound differently at each call, not a second key former.
prefix:
let
  within =
    who: prim:
    let
      door = if builtins.isString who then who else who.door;
    in
    if door == prim then
      prim
    else
      {
        inherit door prim;
        # A site that interpolates `who` directly still reads door-first, never a coercion abort.
        __toString = s: "${s.door} (in ${s.prim})";
      };
  say =
    who: text:
    if builtins.isString who then
      "${prefix}.${who}: ${text}"
    else
      "${prefix}.${who.door}: ${text} (in ${who.prim})";

  # `hasContext` second: on a context-free name the discard is the identity, so skipping it spares
  # the string copy it would make on the path every existing caller is on.
  attrKey =
    who: k:
    if builtins.isString k then
      (if builtins.hasContext k then builtins.unsafeDiscardStringContext k else k)
    else
      throw (notAnIdentifier who k);

  # ── THE IDENTIFIER REFUSAL, WRITTEN ONCE FOR EVERY DOOR THAT TAKES A NODE ID ──
  # Names the type and never the value: the value is not a string, and interpolating it is the
  # coercion abort the refusal exists to replace. `typeOf` is total, so the message cannot itself
  # abort. A door `seq`s its guard ahead of its body, because a body that only compares the id with
  # `==` never forces it into a type error and would answer a plausible wrong value instead
  # (ADR-0025 item 1: a value or a named refusal, never an interpreter error).
  notAnIdentifier = who: v: say who "got ${builtins.typeOf v}, expected a node identifier (a string)";

  # For a door whose body keys, indexes or `attrKey`s the id: only a string is a node id there.
  identifier = who: v: if builtins.isString v then v else throw (notAnIdentifier who v);

  # For a door whose body only hands the id to the caller's accessor, never to `genericClosure`'s
  # own key comparator: such a closure keys on `builtins.toJSON […]`, not on the raw id, so a
  # scalar id never reaches a native cross-type `<` there and `nodeKey` still
  # refuses only the shapes that are never a node id (den-hoag-bkdkg C1), keeping every scalar. The
  # `genericClosure` doors that key on the raw id (`reachableFrom` and its siblings) do NOT use this
  # guard: den-hoag-7gp66 OQ13 ruled (arm a, 2026-09-26) that a node id is a string, so their target
  # checks route through `identifier` above instead, and a scalar other than a string is refused
  # there by name (den-hoag-3w9e7).
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
    if callable f then f else throw (notA surface name "a function returning ${want}" f);
  badResult =
    surface: name: subject: want: v:
    throw (say surface "${name} ${subject} returned a ${builtins.typeOf v}, not ${want}");

  # The same text for caller DATA a constructor reads (den-hoag-ndte): a field, or an element
  # named by its position, that is not the shape the read needs.
  notA =
    surface: what: want: v:
    say surface "${what} is a ${builtins.typeOf v}, not ${want}";

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
      throw (
        say who "the accessor's edges is a ${builtins.typeOf f}, not a function from a node id to a list of node ids"
      );
  notEdgeList =
    who: id: v:
    say who "edges ${renderId id} returned a ${builtins.typeOf v}, not a list of node ids";

  # A RETIRED argument is still accepted and refused by name (ADR-0025 item 1): dropping it from
  # closed formals would meet a stale caller with an uncatchable `unexpected argument`, and
  # ignoring it would leave a door that describes nothing. `preorder.nix`'s header says why the
  # walks no longer have the ceiling `maxDepth` capped.
  retiredMaxDepth =
    who:
    "${prefix}.${who}: maxDepth is retired. This walk is a builtins.genericClosure loop, not a recursion, so it has no depth ceiling for a cap to sit below; remove the argument.";

  nodeKey =
    who: v:
    if builtins.isAttrs v || builtins.isList v || builtins.isFunction v || v == null then
      throw "${prefix}.${who}: got ${builtins.typeOf v}, expected a node identifier (a string or another scalar)"
    else
      v;
in
{
  inherit
    within
    say
    attrKey
    callable
    callableAt
    badResult
    notA
    renderId
    edgesAccessor
    notEdgeList
    retiredMaxDepth
    notAnIdentifier
    identifier
    nodeKey
    ;
  # `genAttrs`, keyed by text: `f` receives the caller's ORIGINAL name, never the key. The former is
  # written out rather than called: this body runs once per key formed, and a call costs an Env.
  keyedAttrs =
    who: names: f:
    builtins.listToAttrs (
      map (n: {
        name =
          if builtins.isString n then
            (if builtins.hasContext n then builtins.unsafeDiscardStringContext n else n)
          else
            throw (notAnIdentifier who n);
        value = f n;
      }) names
    );
}
