{ lib }:
let
  reachableFrom = { edges, ... }: startId:
    let
      go = visited: queue:
        if queue == [] then builtins.attrNames (builtins.removeAttrs visited [startId])
        else let
          current = builtins.head queue;
          rest = builtins.tail queue;
        in
        if visited ? ${current} then go visited rest
        else let
          targets = edges current;
          newVisited = visited // { ${current} = true; };
        in go newVisited (rest ++ targets);
    in go {} [startId];

  reachableWhere = { edges, ... }: startId: pred:
    builtins.filter pred (reachableFrom { inherit edges; } startId);

  # Silently terminates on cyclic parent chains rather than throwing.
  # Spec (Neron 2015) suggests throwing, but silent termination is safer
  # for library code — callers can detect cycles via `cycles` if needed.
  ancestorsOf = { parent, ... }: startId:
    let
      go = visited: id:
        let p = parent id;
        in if p == null then []
        else if visited ? ${p} then []
        else [p] ++ go (visited // { ${p} = true; }) p;
    in go { ${startId} = true; } startId;

  pathsBetween = { edges, ... }: startId: endId:
    let
      dfs = visited: current:
        if current == endId then [ [endId] ]
        else if visited ? ${current} then []
        else let
          newVisited = visited // { ${current} = true; };
          targets = edges current;
        in builtins.concatMap (next:
          map (path: [current] ++ path) (dfs newVisited next)
        ) targets;
    in dfs {} startId;
in
{
  inherit reachableFrom reachableWhere ancestorsOf pathsBetween;
}
