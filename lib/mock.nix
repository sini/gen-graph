{ lib }:
let
  mkNodes =
    {
      edges ? [],
      parents ? [],
      decls ? {},
      types ? {},
    }:
    let
      allIds = lib.unique (
        (lib.concatMap (e: [ e.from e.to ]) edges)
        ++ (lib.concatMap (e: [ e.from e.to ]) parents)
        ++ (builtins.attrNames decls)
        ++ (builtins.attrNames types)
      );
      parentMap = builtins.listToAttrs (map (e: { name = e.from; value = e.to; }) parents);
      importMap = builtins.foldl' (acc: e:
        acc // { ${e.from} = (acc.${e.from} or []) ++ [ e.to ]; }
      ) {} edges;
      childMap = builtins.foldl' (acc: e:
        acc // { ${e.to} = (acc.${e.to} or []) ++ [ e.from ]; }
      ) {} parents;
    in
    lib.genAttrs allIds (id: {
      inherit id;
      parent = parentMap.${id} or null;
      imports = importMap.${id} or [];
      decls = decls.${id} or {};
      type = types.${id} or null;
      childrenIds = childMap.${id} or [];
      edgesByLabel = lib.optionalAttrs (importMap ? ${id}) { I = importMap.${id}; }
        // lib.optionalAttrs (parentMap ? ${id}) { P = [ parentMap.${id} ]; };
      rels = lib.optionalAttrs (decls ? ${id}) { ":" = decls.${id}; };
    });

  fixtures = {
    diamond = mkNodes {
      edges = [ { from = "a"; to = "b"; } { from = "a"; to = "c"; } { from = "b"; to = "d"; } { from = "c"; to = "d"; } ];
    };
    chain = mkNodes {
      edges = [ { from = "a"; to = "b"; } { from = "b"; to = "c"; } { from = "c"; to = "d"; } ];
    };
    cyclic = mkNodes {
      edges = [ { from = "a"; to = "b"; } { from = "b"; to = "c"; } { from = "c"; to = "a"; } ];
    };
    tree = mkNodes {
      parents = [ { from = "child1"; to = "root"; } { from = "child2"; to = "root"; } { from = "grandchild"; to = "child1"; } ];
    };
    serviceGraph = mkNodes {
      edges = [
        { from = "web"; to = "api"; }
        { from = "api"; to = "db"; }
        { from = "api"; to = "cache"; }
        { from = "worker"; to = "db"; }
        { from = "worker"; to = "queue"; }
      ];
      types = { web = "frontend"; api = "backend"; db = "datastore"; cache = "datastore"; worker = "backend"; queue = "datastore"; };
    };
  };
in
{
  inherit mkNodes fixtures;
}
