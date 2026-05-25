{
  description = "gen-graph demo: monotonic graph queries (Arntzenius & Krishnaswami 2016)";

  inputs = {
    gen-graph.url = "github:sini/gen-graph";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { gen-graph, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      graph = gen-graph { inherit lib; };

      # Microservice dependency graph
      #
      #   gateway -> web -> api -> database
      #                         -> cache
      #   worker -> database
      #          -> queue
      #
      # Diamond pattern: gateway and worker both reach database via different paths.
      # Two roots (gateway, worker), three leaves (database, cache, queue).
      nodes = {
        gateway = {
          type = "frontend";
          imports = [ "web" ];
        };
        web = {
          type = "frontend";
          imports = [ "api" ];
        };
        api = {
          type = "backend";
          imports = [ "database" "cache" ];
        };
        worker = {
          type = "backend";
          imports = [ "database" "queue" ];
        };
        database = {
          type = "datastore";
          imports = [ ];
        };
        cache = {
          type = "datastore";
          imports = [ ];
        };
        queue = {
          type = "datastore";
          imports = [ ];
        };
      };

      # Variant with a circular dependency: cache -> api creates a cycle
      cyclicNodes = nodes // {
        cache = {
          type = "datastore";
          imports = [ "api" ];
        };
      };
    in
    {
      # --- Layer 2: Built-in primitives ---

      # What can web reach transitively?
      # -> [ "api" "cache" "database" ]
      webReaches = graph.reachableFrom nodes "web";

      # What breaks if database goes down?
      # -> [ "api" "gateway" "web" "worker" ]
      databaseImpact = graph.impactOf nodes "database";

      # Entry points (no incoming edges)
      # -> [ "gateway" "worker" ]
      entryPoints = graph.roots nodes;

      # Leaf services (no outgoing edges)
      # -> [ "cache" "database" "queue" ]
      leafServices = graph.leaves nodes;

      # All paths from gateway to database
      # -> [ [ "gateway" "web" "api" "database" ] ]
      gatewayToDb = graph.pathsBetween nodes "gateway" "database";

      # Cycle detection on a healthy DAG (should be empty)
      # -> []
      hasCycles = graph.cycles nodes;

      # Cycle detection with circular dependency: cache -> api
      # -> [ "api" "cache" ]
      detectedCycles = graph.cycles cyclicNodes;

      # Predicate-filtered reachability: only datastores reachable from gateway
      # -> [ "cache" "database" ]
      gatewayDatastores = graph.reachableWhere nodes "gateway" (n: n.type == "datastore");

      # --- Layer 1: Monotonic combinators ---

      # Filtering: only backend services
      # -> { api = ...; worker = ...; }
      backends = graph.select nodes (n: n.type == "backend");

      # Edge operations
      allEdges = graph.fromEdges nodes;
      edgeCount = graph.sizeEdges (graph.fromEdges nodes);

      # Fixpoint: transitive closure computed explicitly via compose
      transitiveFromGateway =
        let
          iEdges = graph.selectEdges (graph.fromEdges nodes) (e: e.label == "I");
          closure = graph.fixpoint {
            seed = iEdges;
            step = current: graph.unionEdges current (graph.compose current iEdges);
          };
        in
        builtins.attrNames (closure.gateway or { });
      # -> [ "api" "cache" "database" "web" ]
    };
}
