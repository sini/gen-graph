{ lib }:
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

        edgeIndex = builtins.foldl' (
          acc: e: acc // { ${e.from} = (acc.${e.from} or [ ]) ++ [ e.to ]; }
        ) { } edges;

        parentIndex = builtins.listToAttrs (
          map (e: {
            name = e.from;
            value = e.to;
          }) parents
        );
      in
      {
        edges = id: lib.unique (edgeIndex.${id} or [ ]);
        parent = id: parentIndex.${id} or null;
        nodes = allIds;
        nodeData = id: nodeData.${id} or { };
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
  };
in
self
