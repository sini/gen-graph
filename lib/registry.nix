{ prelude }:
let
  self = {
    fromRegistry =
      {
        registry,
        edges,
        parent ? _id: _entry: null,
      }:
      let
        nodes = builtins.attrNames registry;
      in
      {
        inherit nodes;
        edges = id: edges id (registry.${id} or { });
        parent = id: parent id (registry.${id} or { });
        nodeData = id: registry.${id} or { };
      };

    field =
      name: _id: entry:
      entry.${name} or [ ];

    fields =
      names: _id: entry:
      builtins.concatLists (map (name: entry.${name} or [ ]) names);

    mkGraph =
      {
        edges ? [ ],
        parents ? [ ],
        nodeData ? { },
      }:
      let
        allIds = builtins.attrNames (
          builtins.listToAttrs (
            (map (e: {
              name = e.from;
              value = true;
            }) edges)
            ++ (map (e: {
              name = e.to;
              value = true;
            }) edges)
            ++ (map (e: {
              name = e.from;
              value = true;
            }) parents)
            ++ (map (e: {
              name = e.to;
              value = true;
            }) parents)
            ++ (map (k: {
              name = k;
              value = true;
            }) (builtins.attrNames nodeData))
          )
        );

        edgeIndex =
          let
            grouped = builtins.groupBy (e: e.from) edges;
          in
          builtins.mapAttrs (_: es: map (e: e.to) es) grouped;

        parentIndex = builtins.listToAttrs (
          map (e: {
            name = e.from;
            value = e.to;
          }) parents
        );
      in
      {
        edges = id: prelude.unique (edgeIndex.${id} or [ ]);
        parent = id: parentIndex.${id} or null;
        nodes = allIds;
        nodeData = id: nodeData.${id} or { };
      };

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
        derivedEdges = builtins.concatMap (
          item:
          map (r: {
            from = item.id;
            to = project r;
            inherit item;
            ref = r;
          }) (scan item.value)
        ) items;
      in
      self.mkGraph {
        edges = map (e: { inherit (e) from to; }) derivedEdges;
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
      serviceGraph = self.mkGraph {
        edges = [
          {
            from = "web";
            to = "api";
          }
          {
            from = "api";
            to = "db";
          }
          {
            from = "api";
            to = "cache";
          }
          {
            from = "worker";
            to = "db";
          }
          {
            from = "worker";
            to = "queue";
          }
        ];
        nodeData = {
          web = {
            type = "frontend";
          };
          api = {
            type = "backend";
          };
          db = {
            type = "datastore";
          };
          cache = {
            type = "datastore";
          };
          worker = {
            type = "backend";
          };
          queue = {
            type = "datastore";
          };
        };
      };
    };

    # labeled fixtures — a miniature containment/membership world for query tests.
    #   contains: root→{h1,h2}, h1→{u1,vm1}, vm1→{u2}   (nested depth 3)
    #   member:   g1→{u1,u2}
    #   include:  u1→shared
    labeledFixtures = {
      world = {
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
          .${id} or [ ];
      };
      # labeled cycle: a -contains-> b -contains-> a, plus a -member-> m
      cyclic = {
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
          .${id} or [ ];
      };
      # poison: touching node "boom"'s edges throws — laziness witness. boom has
      # an incoming edge (label "other"), so only the derivative-empty prune (a
      # follow that derives empty on "other") keeps boom's accessor unforced.
      poisoned = {
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
          .${id} or [ ];
      };
    };
  };
in
self
