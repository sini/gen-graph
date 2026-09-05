# Purity invariant (gen-prelude design §5): gen-graph depends only on gen-prelude and
# must import NO `nixpkgs.lib`. This pins "pure" as a checked property, not an
# aspiration — a stray `lib.foo` / `lib.types` / `evalModules` / nixpkgs input creeping
# back into the library source fails CI.
#
# Scope: every `.nix` file under lib/, at any depth, plus the root flake.nix and default.nix
# (the library + its flake). NOT ci/ — the test harness legitimately uses nixpkgs.lib
# (including, here, to do this scan). The walk descends, so a file added under a new lib/
# subdirectory is in scope by construction; a flat listing would let it leave the invariant
# silently, which is the failure this scope is written to exclude rather than to survive.
#
# Labels are repo-root-relative paths, never bare basenames. `lib/default.nix` and the root
# `default.nix` are both in scope, and a bare basename names them with the same string — so a
# violation in one is indistinguishable from a violation in the other, and a red CI names a
# file the reader cannot open. The walk therefore carries a prefix down from the root it was
# handed, and every label it emits is a path relative to the repository root.
#
# AN EMPTINESS IS NOT EVIDENCE (den-hoag-m61n — ported from gen-scope's e4b7f40, the fullest
# composite of the sibling instances of this class). Three mechanisms stand between this
# library and a silent nixpkgs tether — the walk that finds the files, the read that strips
# their comments, and the token scan that judges them — and every one of them reports "clean"
# when it is dead. Each is therefore held to a cell whose expectation is a literal:
#
#   * The SUBJECT is asserted along both of its axes, membership and content, because a scan can
#     be severed from the tree either way. MEMBERSHIP — which files the scan reads — is the label
#     list itself, not its size: disconnection is an identity defect and a non-emptiness guard is
#     a cardinality predicate, so the two do not meet, and a scan that has dropped the whole
#     library tree and kept only the two root entries is non-empty, has non-empty content, and
#     reports the invariant clean over a set containing none of the library. Asserting the list
#     also makes a new library file arrive as a red rather than being absorbed silently, which
#     is the point — the scope of an invariant is a declared surface, not a default.
#   * CONTENT is the axis the manifest is silent on, and it is severable on its own: a read that
#     returned some fixed text for every library file would satisfy the membership list exactly
#     while carrying none of the library's source, and a live tether sitting on disk would go
#     unseen through every other cell here. So the reads are held to a token the library really
#     contains, at the exact labels where it really occurs.
#   * The DETECTOR is exercised over the real subject with one known-bad entry appended, so the
#     cell that proves it fires and the cell that proves the tree is clean are one measurement
#     over one source list rather than two unrelated ones. A detector proven only against a
#     synthetic list says nothing about the pipeline that reads disk.
#   * The WALK's recursion runs against a fixture tree that is nested on purpose, because lib/
#     is flat today (13 files, confirmed `find lib -name '*.nix'` == `-maxdepth 1`) and a walk
#     that quietly stopped descending would keep every other cell green.
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Comment-stripped source: drop everything from the first `#` on each line. Safe here
  # because `#` appears only in comments across these files (no `#` in string literals);
  # documentation may freely mention forbidden tokens without tripping the invariant.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  # ★ THE STRIP'S PREMISE, asserted rather than assumed. `stripComments` cuts each line at a comment
  # marker, and that cut is sound only while the `#` it cuts at stands OUTSIDE a string literal.
  # Where it does not, live code is truncated to the end of that line and every cell below goes
  # blind on what was removed, with no signal at all — a green suite over source nothing scanned.
  #
  # The predicate asks the strip ITSELF where it cut: `stripComments` of a single line is exactly
  # the text before that line's cut. It then asks whether that text closed every double quote it
  # opened, an odd count meaning the cut stands inside a string. Deriving it from `stripComments`
  # rather than restating the cut rule is what keeps premise and strip from drifting apart when one
  # of them is edited, and it is why one block serves both strip families in this ecosystem.
  #
  # It is LINE-LOCAL and so cannot conclude about string content that spans lines — an indented
  # multi-line string block. Those files are declared as a list of their own by
  # `test-strip-premise-multiline-strings` rather than trusted in silence.
  countQuotes = s: (lib.length (lib.splitString "\"" s)) - 1;
  cutIsInString =
    line:
    let
      kept = stripComments line;
    in
    kept != line && lib.mod (countQuotes kept) 2 == 1;

  # premiseBreaches : [ { name; text; } ] -> [ "file:line" ]. A breach is reported at its line as
  # well as its file, because what it says is that one particular line's code was truncated.
  premiseBreaches =
    srcs:
    lib.concatMap (
      src:
      lib.concatLists (
        lib.imap1 (i: line: lib.optional (cutIsInString line) "${src.name}:${toString i}") (
          lib.splitString "\n" src.text
        )
      )
    ) srcs;

  # walk : string -> path -> [ { name; path; } ], `name` being `prefix` extended by the
  # entry's position in the tree — so a violation is reported at a repo-root-relative path a
  # reader can act on, rather than at the store path the sources happen to be evaluated from.
  walk =
    prefix: dir:
    lib.concatLists (
      lib.mapAttrsToList (
        entry: type:
        if type == "directory" then
          walk "${prefix}${entry}/" (dir + "/${entry}")
        else if lib.hasSuffix ".nix" entry then
          [
            {
              name = "${prefix}${entry}";
              path = dir + "/${entry}";
            }
          ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  # ★ THE READ AND THE STRIP ARE SEPARATE STAGES, one `readFile` per file feeding both. The premise
  # cell has to speak about the RAW text, which is only a value once the strip stops happening inside
  # the read; and `sources` is then a total per-element function of `rawSources` — the name passes
  # through, the code is the strip of the text — so pinning either one pins the other, and the cells
  # over each COMPOSE instead of hoping two independent reads of the same tree agree.
  raw =
    entries:
    map (e: {
      inherit (e) name;
      text = builtins.readFile e.path;
    }) entries;

  strip =
    entries:
    map (e: {
      inherit (e) name;
      code = stripComments e.text;
    }) entries;

  rawSources = raw (walk "lib/" libDir) ++ [
    {
      name = "flake.nix";
      text = builtins.readFile ../../flake.nix;
    }
    {
      name = "default.nix";
      text = builtins.readFile ../../default.nix;
    }
  ];

  sources = strip rawSources;

  # Tokens that signal a nixpkgs-lib tether or the module-system (Korora-class) tier.
  forbidden = [
    "nixpkgs" # a nixpkgs flake input / reference
    "lib." # any nixpkgs lib call (lib.types, lib.genAttrs, …)
    "{ lib }" # the old `{ lib }` parameter signature
    "{ lib," # `{ lib, … }` parameter signature
    "evalModules" # module-system tier
    "mkOption" # module-system tier
  ];

  # The live counterpart to `forbidden`: the name this library reaches for where a tether would
  # reach for nixpkgs. Every gen-graph source but TWO carries it, and both exclusions are modules that
  # depend on nothing: `lib/traverse.nix` is the `genericClosure`-based BFS core written in `builtins`
  # alone, and `lib/declared-edges.nix` is the declared relation's vocabulary — its accept-list, force
  # and tag are all `builtins`, so it takes no prelude parameter at all. Those exclusions are what give
  # the assertion its teeth: the expected
  # list is a PROPER subset of the manifest, so a read returning one fixed text for every file
  # lands outside it either way — without the token the list collapses toward empty, with it the
  # list swells to every source.
  liveToken = "prelude";
  liveReads = map (src: src.name) (lib.filter (src: genPrelude.hasInfix liveToken src.code) sources);

  # scan : [ { name; code; } ] -> [ "file: 'tok'" ]
  scan =
    srcs:
    lib.concatMap (
      src:
      map (tok: "${src.name}: '${tok}'") (lib.filter (tok: genPrelude.hasInfix tok src.code) forbidden)
    ) srcs;
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-lib-free = {
    expr = scan sources;
    expected = [ ];
  };

  # What the cell above is a statement ABOUT. Its `[ ]` is produced just as readily by a scan
  # that reads the wrong tree, or no tree, as by a library that is clean, and neither the
  # detector cells below nor a guard on the source list's size can tell those apart — the first
  # never touch `sources`, and the second answers a question about how many rather than which.
  # The library tree is small and its membership is a deliberate surface, so it is written down.
  flake.tests.purity.test-scan-subject-is-the-library-tree = {
    expr = map (s: s.name) sources;
    expected = [
      "lib/declared-edges.nix"
      "lib/default.nix"
      "lib/edge-maps.nix"
      "lib/endpoints.nix"
      "lib/enumerate.nix"
      "lib/fixpoint.nix"
      "lib/global.nix"
      "lib/order.nix"
      "lib/partition.nix"
      "lib/preorder.nix"
      "lib/query.nix"
      "lib/regex.nix"
      "lib/registry.nix"
      "lib/traverse.nix"
      "flake.nix"
      "default.nix"
    ];
  };

  # And that those labels carry their files' text. The manifest above pins membership and is
  # silent on content: a `read` that handed every library entry one fixed string would satisfy it
  # exactly, and a live `lib.types.str` sitting in a real library file would pass through all of
  # the other cells here at exit 0. This is the same shape as the manifest — an exact list, not a
  # count — asked of a token that is genuinely present rather than genuinely absent, so the reads
  # are shown to carry this repository's source and not a constant.
  flake.tests.purity.test-scan-reads-are-live = {
    expr = liveReads;
    expected = [
      "lib/default.nix"
      "lib/edge-maps.nix"
      "lib/endpoints.nix"
      "lib/enumerate.nix"
      "lib/fixpoint.nix"
      "lib/global.nix"
      "lib/order.nix"
      "lib/partition.nix"
      "lib/preorder.nix"
      "lib/query.nix"
      "lib/regex.nix"
      "lib/registry.nix"
      "flake.nix"
      "default.nix"
    ];
  };

  # The detector has teeth, and it grows them on the real subject: the scan runs over exactly
  # the source list the cell above asserts, with one synthetic entry appended. So the firing is
  # proven by the same call that reports the tree clean, and the expectation states both halves
  # at once — the library contributes nothing and the planted tether contributes precisely this.
  #
  # The expectation is the violation LIST, not merely that one was produced: a detector that
  # fires on the wrong token, or whose `file: 'tok'` message has decayed into something a reader
  # cannot act on, is broken in the way that matters and a bare non-emptiness check would pass
  # it. The synthetic entry is never written to disk, and its label is bracketed so it cannot be
  # read as one of the repo-root-relative paths it now sits beside.
  flake.tests.purity.test-detector-catches-injected-violation = {
    expr = scan (
      sources
      ++ [
        {
          name = "<injected>";
          code = stripComments "  foo = lib.types.str; # comment mentioning nixpkgs is stripped";
        }
      ]
    );
    expected = [ "<injected>: 'lib.'" ];
  };

  # And it does not "catch" a token that only appears inside a comment. This is the other half
  # of the same instrument, and it is asked in isolation because what it discriminates is
  # comment from code: the strip is load-bearing on real source — the root flake.nix and
  # default.nix both discuss nixpkgs/gen-prelude in prose — so a strip that silently stopped
  # running would red the library cell for reasons that are not tethers.
  flake.tests.purity.test-comments-are-stripped = {
    expr = scan [
      {
        name = "<comment-only>";
        code = stripComments "  x = 1; # this line mentions mkOption and nixpkgs but is a comment";
      }
    ];
    expected = [ ];
  };

  # The walk descends, and carries its prefix while doing so. lib/ is flat today, so the library
  # cell exercises the recursive branch not at all and would keep passing if the walk quietly
  # flattened; the fixture tree is nested on purpose and carries a planted tether at each of its
  # two depths. Handing it a non-empty prefix — its own real position in the repository — pins
  # both halves of the naming rule: the prefix the walk is given is threaded through, and the
  # prefix it builds for a subdirectory extends that one rather than replacing it.
  flake.tests.purity.test-walk-descends-into-subdirectories = {
    expr = scan (strip (raw (walk "ci/tests/_fixtures/purity-walk/" ./_fixtures/purity-walk)));
    expected = [
      "ci/tests/_fixtures/purity-walk/nested/tethered.nix: 'lib.'"
      "ci/tests/_fixtures/purity-walk/surface.nix: 'mkOption'"
    ];
  };

  # ★ THE PREMISE HOLDS OF THE TEXT THAT WAS ACTUALLY SCANNED. This is an absence claim over text
  # read from disk and it is NOT non-vacuous on its own: its expectation is `[ ]`, which an emptied
  # or constant subject satisfies exactly as a sound corpus does — a scan of nothing breaches no
  # premise. What arms it is the subject-pinning asserted over this same `rawSources` read, together
  # with the live control below for the predicate itself; green here means the premise holds of the
  # text those cells pin, and nothing more.
  flake.tests.purity.test-strip-premise-holds = {
    expr = premiseBreaches rawSources;
    expected = [ ];
  };

  # And the predicate is capable of saying no. Its subject is a literal written inside this cell
  # rather than anything on disk, so it is UNSEVERABLE from the tree and establishes exactly that the
  # test discriminates an in-string `#` from an ordinary trailing comment — it says nothing whatever
  # about what the cell above was pointed at, and it is NOT that cell's arming. Both directions ride
  # in one expectation: line 1 must be caught and line 2 must not, so a predicate stuck at either
  # constant reds here. The literal cuts under BOTH strip families in this ecosystem — its `#` is
  # whitespace-preceded, so a comment-start strip cuts there too and the control cannot go dead by
  # being pasted into a repository whose strip is the other one.
  flake.tests.purity.test-strip-premise-scan-is-live = {
    expr = premiseBreaches [
      {
        name = "<in-string-hash>";
        text = ''
          url = "a b # c";
          x = 1; # an ordinary trailing comment
        '';
      }
    ];
    expected = [ "<in-string-hash>:1" ];
  };

  # The declared surface: the files the line-local predicate cannot conclude about. An indented
  # multi-line string block carries string content across line boundaries, where a per-line quote
  # count cannot follow it, so those files are written down rather than trusted in silence. The first
  # file to grow one arrives as a red that has to be READ, exactly as a new library file arrives as a
  # red on a membership manifest.
  flake.tests.purity.test-strip-premise-multiline-strings = {
    expr = map (s: s.name) (lib.filter (s: genPrelude.hasInfix "''" s.text) rawSources);
    expected = [ ];
  };
}
