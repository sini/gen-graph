{
  description = "gen-graph demo: accessor-based graph queries";

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
      services = {
        gateway = { type = "frontend"; deps = [ "web" ]; };
        web = { type = "frontend"; deps = [ "api" ]; };
        api = { type = "backend"; deps = [ "database" "cache" ]; };
        worker = { type = "backend"; deps = [ "database" "queue" ]; };
        database = { type = "datastore"; deps = []; };
        cache = { type = "datastore"; deps = []; };
        queue = { type = "datastore"; deps = []; };
      };

      # Accessor record over the service data
      g = {
        edges = id: (services.${id} or { deps = []; }).deps;
        parent = _: null;
        nodes = builtins.attrNames services;
        nodeData = id: services.${id} or {};
      };

      # Variant with a circular dependency: cache -> api creates a cycle
      cyclicServices = services // {
        cache = { type = "datastore"; deps = [ "api" ]; };
      };
      gCyclic = g // {
        edges = id: (cyclicServices.${id} or { deps = []; }).deps;
        nodes = builtins.attrNames cyclicServices;
        nodeData = id: cyclicServices.${id} or {};
      };
    in
    {
      # --- Lazy Traversal ---

      # What can web reach transitively?
      # → [ "api" "cache" "database" ]
      webReaches = graph.reachableFrom g "web";

      # All paths from gateway to database
      # → [ [ "gateway" "web" "api" "database" ] ]
      gatewayToDb = graph.pathsBetween g "gateway" "database";

      # Predicate-filtered reachability: only datastore IDs reachable from gateway
      # → [ "cache" "database" ]
      gatewayDatastores = graph.reachableWhere g "gateway" (id:
        ((services.${id} or {}).type or null) == "datastore"
      );

      # --- Global Analysis ---

      # What breaks if database goes down? (reverse transitive reachability)
      # → [ "api" "gateway" "web" "worker" ]
      databaseImpact = graph.dependents g "database";

      # Cycle detection on a healthy DAG (should be empty)
      # → []
      noCycles = graph.cycles g;

      # Cycle detection with circular dependency: cache → api → cache
      # → [ "api" "cache" ]
      detectedCycles = graph.cycles gCyclic;

      # Reversed graph: who depends on database?
      # → [ "api" "worker" ]
      dbDependedOnBy = let rev = graph.transpose g; in rev.edges "database";

      # --- Enumeration ---

      # Entry points (no incoming edges)
      # → [ "gateway" "worker" ]
      entryPoints = graph.roots g;

      # Leaf services (no outgoing edges)
      # → [ "cache" "database" "queue" ]
      leafServices = graph.leaves g;

      # Filter by node data: only backend services
      # → [ "api" "worker" ]
      backends = graph.select g (d: (d.type or null) == "backend");

      # --- Materialization + Edge Map Operations ---

      # Materialize to edge map
      edgeMap = graph.materialize g;

      # Transitive closure: full reachability as edge map
      closure = graph.transitiveClosure g;

      # Transitive reduction: minimal edges preserving reachability
      minimal = graph.transitiveReduction g;

      # Edge filtering: only edges targeting datastores
      datastoreEdges = let em = graph.materialize g; in
        graph.selectEdges
          (_from: to: ((services.${to} or {}).type or null) == "datastore")
          em;

      # Compose: two-hop reachability
      # a → b in edgeMap, b → c in edgeMap ⟹ a → c in twoHop
      twoHop = let em = graph.materialize g; in graph.compose em em;

      # --- Mock utility: fromNodeMap for legacy data ---

      # Convert old-format node map to accessor record
      legacyReachable = let
        legacyData = {
          "svc:web" = { imports = [ "svc:api" ]; parent = null; };
          "svc:api" = { imports = [ "svc:db" ]; parent = "svc:web"; };
          "svc:db" = { imports = []; parent = "svc:api"; };
        };
        legacyG = graph.mock.fromNodeMap legacyData;
      in graph.reachableFrom legacyG "svc:web";
      # → [ "svc:api" "svc:db" ]

      legacyAncestors = let
        legacyData = {
          "svc:web" = { imports = [ "svc:api" ]; parent = null; };
          "svc:api" = { imports = [ "svc:db" ]; parent = "svc:web"; };
          "svc:db" = { imports = []; parent = "svc:api"; };
        };
        legacyG = graph.mock.fromNodeMap legacyData;
      in graph.ancestorsOf legacyG "svc:db";
      # → [ "svc:api" "svc:web" ]
    };
}
