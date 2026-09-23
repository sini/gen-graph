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
in
{
  inherit attrKey;
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
