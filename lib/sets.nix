# Result set operations for monotonic graph queries.
# Node sets: { nodeId = nodeRecord; }
# Edge sets: { from = { to = edgeRecord; }; }
{ lib }:
{
  emptyNodes = {};
  emptyEdges = {};

  fromNodes = nodes: nodes;

  fromEdges = nodes:
    let
      allEdges = lib.concatLists (lib.mapAttrsToList (id: node:
        (builtins.map (target: {
          from = id;
          to = target;
          label = "I";
        }) (node.imports or []))
        ++ (lib.optional ((node.parent or null) != null) {
          from = id;
          to = node.parent;
          label = "P";
        })
        ++ (lib.concatLists (lib.mapAttrsToList (label: targets:
          builtins.map (target: {
            from = id;
            to = target;
            inherit label;
          }) targets
        ) (builtins.removeAttrs (node.edgesByLabel or {}) [ "P" "I" ])))
      ) nodes);
    in
    builtins.foldl' (acc: e:
      let existing = acc.${e.from} or {};
      in acc // { ${e.from} = existing // { ${e.to} = e; }; }
    ) {} allEdges;

  unionNodes = a: b: a // b;

  unionEdges = a: b:
    builtins.foldl' (acc: fromId:
      let
        existing = acc.${fromId} or {};
        new = b.${fromId};
      in
      acc // { ${fromId} = existing // new; }
    ) a (builtins.attrNames b);

  intersectNodes = a: b:
    lib.filterAttrs (id: _: b ? ${id}) a;

  intersectEdges = a: b:
    lib.filterAttrs (_: targets: targets != {}) (
      lib.mapAttrs (from: aTargets:
        lib.filterAttrs (to: _: (b.${from} or {}) ? ${to}) aTargets
      ) (lib.filterAttrs (from: _: b ? ${from}) a)
    );

  size = s: builtins.length (builtins.attrNames s);
  sizeNodes = s: builtins.length (builtins.attrNames s);

  sizeEdges = s:
    builtins.foldl' (acc: fromId:
      acc + builtins.length (builtins.attrNames s.${fromId})
    ) 0 (builtins.attrNames s);

  memberNode = s: id: s ? ${id};
}
