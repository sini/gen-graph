{ prelude }:
let
  inherit (import ./key.nix)
    attrKey
    badResult
    callable
    callableAt
    notA
    renderId
    ;

  # ── THE CONSTRUCTION FAMILY'S REFUSALS (den-hoag-ndte, ADR-0025 item 1) ──
  # A constructor reads caller DATA, and a read that met the wrong shape aborted past `tryEval`.
  # Each read is guarded where it already was, never pre-scanned, so a refusal fires exactly where
  # the unguarded read died or misread: the discipline `lib/query.nix` states for the accessor's
  # result. SHAPE (a list, a record, a field present) is checked at every read; an endpoint's
  # STRINGNESS only where the constructor KEYS it (`key.nix` `identifier`, den-hoag-bkdkg): a read
  # that passes an endpoint through unkeyed is den-hoag-3w9e7's, which rules what a node id is.
  # Messages name the type and the POSITION, never the value (a refusal that coerced caller data
  # would abort in the act of refusing), and the door the caller invoked (den-hoag-7gp66 Q2 (ii)).
  # An element's "has no 'X'" is a data record's required-field check, kept local as
  # `mkDeclaredEdges` keeps its own: the shared required-field check of the uniform-API grammar
  # (`specs/2026-09-25-gen-uniform-api-grammar-spec.md` P1) is APPLIED to a door's native formals,
  # not to the elements of a field the door already accepts.
  listAt =
    who: what: want: v:
    if builtins.isList v then v else throw (notA who what want v);
  setAt =
    who: what: want: v:
    if builtins.isAttrs v then v else throw (notA who what want v);

  # The first element of `xs` whose `field` fails, rendered. Reached only on the refusal path, so
  # the success path pays no index. Every test is total, so the search cannot abort.
  endFinding =
    who: what: keyed: field: xs:
    let
      bad = e: !(builtins.isAttrs e) || !(e ? ${field}) || (keyed && !(builtins.isString e.${field}));
      i = builtins.head (
        builtins.filter (j: bad (builtins.elemAt xs j)) (builtins.genList (j: j) (builtins.length xs))
      );
      e = builtins.elemAt xs i;
      at = "gen-graph.${who}: ${what} element ${toString i}";
    in
    if !(builtins.isAttrs e) then
      "${at} is a ${builtins.typeOf e}, not a { from; to; } record"
    else if !(e ? ${field}) then
      "${at} has no '${field}'"
    else
      "${at}: '${field}' is a ${builtins.typeOf e.${field}}, not a node identifier (a string)";
  # Bound by the door's name, so `fromScan` refuses a malformed `parents` under its own. The
  # FORMALS stay on each published binding: Nix names the lambda that owns them in its own
  # unexpected-argument message, and that message must keep naming the door.
  mkGraphAs =
    who:
    {
      edges,
      parents,
      nodeData,
    }:
    let
      es = listAt who "edges" "a list of { from; to; } records" edges;
      ps = listAt who "parents" "a list of { from; to; } records" parents;
      nd = setAt who "nodeData" "an attrset from a node identifier to its data" nodeData;
      # The keyed reads are written out at each site, as `key.nix` asks of a check run once per
      # element: a call costs an Env. The rendered refusal is reached only on the refusal path.
      allIds = builtins.attrValues (
        builtins.listToAttrs (
          (map (
            e:
            if builtins.isAttrs e && e ? from && builtins.isString e.from then
              {
                name = attrKey e.from;
                value = e.from;
              }
            else
              throw (endFinding who "edges" true "from" es)
          ) es)
          ++ (map (
            e:
            if builtins.isAttrs e && e ? to && builtins.isString e.to then
              {
                name = attrKey e.to;
                value = e.to;
              }
            else
              throw (endFinding who "edges" true "to" es)
          ) es)
          ++ (map (
            e:
            if builtins.isAttrs e && e ? from && builtins.isString e.from then
              {
                name = attrKey e.from;
                value = e.from;
              }
            else
              throw (endFinding who "parents" true "from" ps)
          ) ps)
          ++ (map (
            e:
            if builtins.isAttrs e && e ? to && builtins.isString e.to then
              {
                name = attrKey e.to;
                value = e.to;
              }
            else
              throw (endFinding who "parents" true "to" ps)
          ) ps)
          ++ (map (k: {
            name = k;
            value = k;
          }) (builtins.attrNames nd))
        )
      );

      edgeIndex =
        let
          grouped = builtins.groupBy (
            e:
            if builtins.isAttrs e && e ? from && builtins.isString e.from then
              attrKey e.from
            else
              throw (endFinding who "edges" true "from" es)
          ) es;
        in
        builtins.mapAttrs (
          _: map (e: if e ? to then e.to else throw (endFinding who "edges" false "to" es))
        ) grouped;

      parentIndex = builtins.listToAttrs (
        map (
          e:
          if builtins.isAttrs e && e ? from && builtins.isString e.from then
            {
              name = attrKey e.from;
              value = if e ? to then e.to else throw (endFinding who "parents" false "to" ps);
            }
          else
            throw (endFinding who "parents" true "from" ps)
        ) ps
      );
    in
    {
      edges = id: prelude.unique (edgeIndex.${attrKey id} or [ ]);
      parent = id: parentIndex.${attrKey id} or null;
      nodes = allIds;
      nodeData = id: nd.${attrKey id} or { };
    };

  self = {
    fromRegistry =
      {
        registry,
        edges,
        parent ? _id: _entry: null,
      }:
      let
        registry' =
          setAt "fromRegistry" "registry" "an attrset from a node identifier to its entry"
            registry;
        nodes = builtins.attrNames registry';
        # Applied inside the accessor this returns, so a non-function is refused where it is first
        # applied; the result is the downstream surface's to read, and that surface checks it.
        e =
          if builtins.isFunction edges || callable edges then
            edges
          else
            throw "gen-graph.fromRegistry: edges is a ${builtins.typeOf edges}, not a function from a node id and its registry entry to a list of node ids";
      in
      {
        inherit nodes;
        # both are applied to the id and then to its entry, so the first application must return a
        # function; its final result is the downstream surface's to read
        edges =
          id:
          let
            h = e id;
          in
          if builtins.isFunction h || callable h then
            h (registry'.${attrKey id} or { })
          else
            badResult "fromRegistry" "edges" (renderId id)
              "a function from a registry entry to a list of node ids"
              h;
        parent =
          let
            pa = callableAt "fromRegistry" "parent" "a node id or null" parent;
          in
          id:
          let
            h = pa id;
          in
          if builtins.isFunction h || callable h then
            h (registry'.${attrKey id} or { })
          else
            badResult "fromRegistry" "parent" (renderId id)
              "a function from a registry entry to a node id or null"
              h;
        nodeData = id: registry'.${attrKey id} or { };
      };

    # The name is the key the extractor reads, so it is checked once, at the first read.
    field =
      name:
      let
        n =
          if builtins.isString name then
            name
          else
            throw (notA "field" "name" "an attribute name (a string)" name);
      in
      _id: entry: entry.${n} or [ ];

    fields =
      names:
      let
        ns = builtins.genList (
          i:
          let
            n = builtins.elemAt names' i;
          in
          if builtins.isString n then
            n
          else
            throw (notA "fields" "names element ${toString i}" "an attribute name (a string)" n)
        ) (builtins.length names');
        names' = listAt "fields" "names" "a list of attribute names" names;
      in
      _id: entry: builtins.concatLists (map (name: entry.${name} or [ ]) ns);

    mkGraph =
      {
        edges ? [ ],
        parents ? [ ],
        nodeData ? { },
      }:
      mkGraphAs "mkGraph" { inherit edges parents nodeData; };

    # fromScan — the graph a REFERENCE SCAN derives. Given a collection of scannable items, a
    # scan reading the references out of an item's value, and a projection from a reference to the
    # id it names, the edge set is CONSTRUCTED rather than declared — which is what makes the
    # dependency structure knowable before any value is produced (Mokhov, Mitchell & Peyton Jones,
    # *Build Systems à la Carte*, ICFP 2018, §3: applicative task dependencies are a function of
    # the task description, not of running it).
    #
    # Nothing here knows what a reference IS. The scan and the projection arrive as arguments, so
    # the scanned domain's vocabulary stays with the caller and ids stay opaque strings: a caller
    # keying nodes by a compound address such as `<identity>:<field>` is indistinguishable from one
    # keying by a bare name, and no separator is ever interpreted.
    #
    # Two contract points a caller depends on. `nodeData`'s keys SEED nodes, as they do for
    # mkGraph, and items do not: an item the scan finds nothing in, and that nothing references,
    # is absent from an edge-derived node set unless the caller names it here. And the derived
    # edges come back beside the accessor, each carrying the item and the reference that produced
    # it, so a caller wanting the reference's own payload reads it off the edge rather than
    # scanning a second time. ★ That second point DEPARTS from a pure "returns an accessor"
    # signature, and it is deliberate: the alternative is running the scan twice over every value
    # — once to derive the edges here, once in the caller to name what each hop meant — and this
    # is the shipped ref-graph path, not a cold one.
    #
    # `parents` forwards to mkGraph untouched. A derived graph still has a containment dimension:
    # gen-schema's kind topology unions a `parent` edge set with the ref edges this derives, and a
    # constructor that dropped `parents` would push that caller back to mkGraph and out of the
    # derivation entirely.
    #
    # NOT the other three constructors, and each for its own reason. `mkGraph` takes an edge list
    # a caller already holds — the derivation is precisely what it does not do. `fromRegistry`
    # sets `nodes = builtins.attrNames registry`, so EVERY entry is a node whether or not anything
    # touches it: the exact negation of the seeding contract above, which
    # `test-items-do-not-seed-nodes` pins — building on it would silently widen a scanned
    # collection into a node set. It also returns no derived edges, so the reference behind a hop
    # would be unrecoverable without a second scan. `field`/`fields` are edge extractors reading a
    # DECLARED list off an entry — a declaration is what a derivation replaces — and they hand
    # back no reference either.
    fromScan =
      {
        items,
        scan,
        project,
        nodeData ? { },
        parents ? [ ],
      }:
      let
        sc = callableAt "fromScan" "scan" "a list of references" scan;
        pj = callableAt "fromScan" "project" "a node id (a string)" project;
        its = listAt "fromScan" "items" "a list of { id; value; } items" items;
        n = builtins.length its;
        # The item's shape is read by the scan, at the spine; its id where it is read. An item
        # with no string id is named by its position.
        itemAt =
          i:
          let
            item = builtins.elemAt its i;
          in
          if !(builtins.isAttrs item) then
            throw (notA "fromScan" "items element ${toString i}" "an { id; value; } item" item)
          else
            item;
        valueOf =
          i: item:
          if item ? value then
            item.value
          else
            throw "gen-graph.fromScan: items element ${toString i} has no 'value'";
        idOf =
          i: item:
          if item ? id then item.id else throw "gen-graph.fromScan: items element ${toString i} has no 'id'";
        nameOf = i: item: if item ? id then renderId item.id else "at position ${toString i}";
        perItem = builtins.genList (
          i:
          let
            item = itemAt i;
          in
          map
            (r: {
              from = idOf i item;
              to =
                let
                  t = pj r;
                in
                if builtins.isString t then
                  t
                else
                  badResult "fromScan" "project" "on a reference of the item ${nameOf i item}" "a node id (a string)"
                    t;
              inherit item;
              ref = r;
            })
            (
              let
                xs = sc (valueOf i item);
              in
              if builtins.isList xs then
                xs
              else
                badResult "fromScan" "scan" "on the item ${nameOf i item}" "a list of references" xs
            )
        ) n;
        derivedEdges = builtins.concatLists perItem;
        # The graph KEYS each source, so it is handed the id checked for stringness; the published
        # `derivedEdges` carry it as read (den-hoag-3w9e7 rules the unkeyed read).
        keyedEdges = builtins.concatLists (
          builtins.genList (
            i:
            let
              id =
                let
                  v = idOf i (itemAt i);
                in
                if builtins.isString v then
                  v
                else
                  throw "gen-graph.fromScan: items element ${toString i}: 'id' is a ${builtins.typeOf v}, not a node identifier (a string)";
            in
            map (e: {
              from = id;
              inherit (e) to;
            }) (builtins.elemAt perItem i)
          ) n
        );
      in
      mkGraphAs "fromScan" {
        edges = keyedEdges;
        inherit nodeData parents;
      }
      // {
        inherit derivedEdges;
      };

    fixtures = {
      diamond = self.mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "a";
            to = "c";
          }
          {
            from = "b";
            to = "d";
          }
          {
            from = "c";
            to = "d";
          }
        ];
      };
      chain = self.mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "c";
          }
          {
            from = "c";
            to = "d";
          }
        ];
      };
      cyclic = self.mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "c";
          }
          {
            from = "c";
            to = "a";
          }
        ];
      };
      tree = self.mkGraph {
        parents = [
          {
            from = "child1";
            to = "root";
          }
          {
            from = "child2";
            to = "root";
          }
          {
            from = "grandchild";
            to = "child1";
          }
        ];
      };
      disconnected = self.mkGraph {
        edges = [
          {
            from = "a";
            to = "b";
          }
        ];
        nodeData = {
          a = {
            type = "connected";
          };
          b = {
            type = "connected";
          };
          island = {
            type = "isolated";
          };
        };
      };
      # A typed attributed graph (Ehrig, Prange & Ehrig 2006, §5): two sources, reconvergent sinks,
      # every node carrying a `type`. Ids and types are invented. `disconnected` carries typed
      # nodeData too, so the name records the fixture's use, not a property only it has.
      attributed = self.mkGraph {
        edges = [
          {
            from = "elm";
            to = "alder";
          }
          {
            from = "alder";
            to = "cedar";
          }
          {
            from = "alder";
            to = "birch";
          }
          {
            from = "fir";
            to = "cedar";
          }
          {
            from = "fir";
            to = "dogwood";
          }
        ];
        nodeData = {
          elm = {
            type = "frond";
          };
          alder = {
            type = "bough";
          };
          cedar = {
            type = "burl";
          };
          birch = {
            type = "burl";
          };
          fir = {
            type = "bough";
          };
          dogwood = {
            type = "burl";
          };
        };
      };
    };

    # labeled fixtures — a miniature containment/membership world for query tests.
    #   contains: root→{h1,h2}, h1→{u1,vm1}, vm1→{u2}   (nested depth 3)
    #   member:   g1→{u1,u2}
    #   include:  u1→shared
    #
    # Each carries its NODE SET: the labeled contract is total (`lib/query.nix`), so a
    # fixture without one is not a labeled graph and could not reach a global surface
    # through `forgetLabels`.
    labeledFixtures = {
      world = {
        nodes = [
          "g1"
          "h1"
          "h2"
          "root"
          "shared"
          "u1"
          "u2"
          "vm1"
        ];
        labeledEdges =
          id:
          {
            root = [
              {
                label = "contains";
                target = "h1";
              }
              {
                label = "contains";
                target = "h2";
              }
            ];
            h1 = [
              {
                label = "contains";
                target = "u1";
              }
              {
                label = "contains";
                target = "vm1";
              }
            ];
            vm1 = [
              {
                label = "contains";
                target = "u2";
              }
            ];
            g1 = [
              {
                label = "member";
                target = "u1";
              }
              {
                label = "member";
                target = "u2";
              }
            ];
            u1 = [
              {
                label = "include";
                target = "shared";
              }
            ];
          }
          .${attrKey id} or [ ];
      };
      # labeled cycle: a -contains-> b -contains-> a, plus a -member-> m
      cyclic = {
        nodes = [
          "a"
          "b"
          "m"
        ];
        labeledEdges =
          id:
          {
            a = [
              {
                label = "contains";
                target = "b";
              }
              {
                label = "member";
                target = "m";
              }
            ];
            b = [
              {
                label = "contains";
                target = "a";
              }
            ];
          }
          .${attrKey id} or [ ];
      };
      # poison: touching node "boom"'s edges throws — laziness witness. boom has
      # an incoming edge (label "other"), so only the derivative-empty prune (a
      # follow that derives empty on "other") keeps boom's accessor unforced.
      poisoned = {
        nodes = [
          "a"
          "b"
          "boom"
        ];
        labeledEdges =
          id:
          {
            a = [
              {
                label = "safe";
                target = "b";
              }
              {
                label = "other";
                target = "boom";
              }
            ];
            b = [ ];
            boom = throw "poisoned accessor forced";
          }
          .${attrKey id} or [ ];
      };
    };
  };
in
self
