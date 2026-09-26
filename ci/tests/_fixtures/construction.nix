# NOT A SUITE. The malformed constructions `ci/tests/construction.nix` asserts catchable and
# `ci/tests-error.nix` (`construction`) pins by message, held once so both assert about the same
# objects. Each refusal carries its well-formed TWIN, read the same way, which the error plane
# evaluates as its inline control: a build that refused everything would refuse the twin too.
{ genGraph }:
let
  G = genGraph;
  e = from: to: { inherit from to; };
  ok = e "a" "b";
  scan = {
    items = [
      {
        id = "a";
        value = [ "b" ];
      }
    ];
    scan = v: v;
    project = r: r;
  };
  sc = a: G.fromScan (scan // a);
  refusal = door: text: bad: good: {
    inherit
      door
      text
      bad
      good
      ;
  };
in
{
  # one entry per refusal text, each on a single-defect construction
  refusals = {
    mkGraph-edges-not-a-list =
      refusal "mkGraph" "edges is a string, not a list of { from; to; } records"
        (G.mkGraph { edges = "x"; }).nodes
        (G.mkGraph { edges = [ ok ]; }).nodes;
    mkGraph-parents-not-a-list =
      refusal "mkGraph" "parents is a int, not a list of { from; to; } records"
        ((G.mkGraph { parents = 1; }).parent "a")
        ((G.mkGraph { parents = [ ok ]; }).parent "a");
    # element 1, so the position is read off the element rather than written in
    mkGraph-edges-element-not-a-record =
      refusal "mkGraph" "edges element 1 is a int, not a { from; to; } record"
        (G.mkGraph {
          edges = [
            ok
            1
          ];
        }).nodes
        (G.mkGraph {
          edges = [
            ok
            ok
          ];
        }).nodes;
    mkGraph-parents-element-not-a-record =
      refusal "mkGraph" "parents element 0 is a int, not a { from; to; } record"
        (G.mkGraph { parents = [ 1 ]; }).nodes
        (G.mkGraph { parents = [ ok ]; }).nodes;
    mkGraph-edges-no-from =
      refusal "mkGraph" "edges element 0 has no 'from'" (G.mkGraph { edges = [ { to = "b"; } ]; }).nodes
        (G.mkGraph { edges = [ ok ]; }).nodes;
    mkGraph-edges-no-to =
      refusal "mkGraph" "edges element 0 has no 'to'" (G.mkGraph { edges = [ { from = "a"; } ]; }).nodes
        (G.mkGraph { edges = [ ok ]; }).nodes;
    mkGraph-parents-no-from =
      refusal "mkGraph" "parents element 0 has no 'from'"
        (G.mkGraph { parents = [ { to = "b"; } ]; }).nodes
        (G.mkGraph { parents = [ ok ]; }).nodes;
    # read through `parent`, the unkeyed value read, which checks presence only
    mkGraph-parents-no-to = refusal "mkGraph" "parents element 0 has no 'to'" (
      (G.mkGraph { parents = [ { from = "a"; } ]; }).parent
        "a"
    ) ((G.mkGraph { parents = [ ok ]; }).parent "a");
    mkGraph-edges-from-not-a-string =
      refusal "mkGraph" "edges element 0: 'from' is a int, not a node identifier (a string)"
        (G.mkGraph { edges = [ (e 42 "b") ]; }).nodes
        (G.mkGraph { edges = [ ok ]; }).nodes;
    mkGraph-edges-to-not-a-string =
      refusal "mkGraph" "edges element 0: 'to' is a int, not a node identifier (a string)"
        (G.mkGraph { edges = [ (e "a" 42) ]; }).nodes
        (G.mkGraph { edges = [ ok ]; }).nodes;
    mkGraph-parents-from-not-a-string =
      refusal "mkGraph" "parents element 0: 'from' is a int, not a node identifier (a string)"
        ((G.mkGraph { parents = [ (e 42 "b") ]; }).parent "b")
        ((G.mkGraph { parents = [ ok ]; }).parent "b");
    mkGraph-parents-to-not-a-string =
      refusal "mkGraph" "parents element 0: 'to' is a int, not a node identifier (a string)"
        (G.mkGraph { parents = [ (e "a" 42) ]; }).nodes
        (G.mkGraph { parents = [ ok ]; }).nodes;
    # read through the accessor, where the unguarded read answered `{ }` (a misread)
    mkGraph-nodeData-not-a-set =
      refusal "mkGraph" "nodeData is a list, not an attrset from a node identifier to its data"
        ((G.mkGraph { nodeData = [ ]; }).nodeData "a")
        ((G.mkGraph { nodeData = { }; }).nodeData "a");
    fromScan-items-not-a-list =
      refusal "fromScan" "items is a string, not a list of { id; value; } items"
        (sc { items = "x"; }).nodes
        (sc { }).nodes;
    fromScan-item-not-a-record =
      refusal "fromScan" "items element 0 is a int, not an { id; value; } item"
        (sc { items = [ 1 ]; }).nodes
        (sc { }).nodes;
    fromScan-item-no-id =
      refusal "fromScan" "items element 1 has no 'id'"
        (sc {
          items = scan.items ++ [ { value = [ "c" ]; } ];
        }).nodes
        (sc {
          items = scan.items ++ [
            {
              id = "c";
              value = [ "c" ];
            }
          ];
        }).nodes;
    fromScan-item-no-value =
      refusal "fromScan" "items element 0 has no 'value'" (sc { items = [ { id = "a"; } ]; }).nodes
        (sc { }).nodes;
    fromScan-id-not-a-string =
      refusal "fromScan" "items element 0: 'id' is a int, not a node identifier (a string)"
        (sc {
          items = [
            {
              id = 42;
              value = [ "b" ];
            }
          ];
        }).nodes
        (sc { }).nodes;
    # the refusal used to render the missing id, and aborted while refusing
    fromScan-scan-result-item-without-id =
      refusal "fromScan" "scan on the item at position 0 returned a int, not a list of references"
        (sc {
          items = [ { value = [ "b" ]; } ];
          scan = _: 1;
        }).nodes
        (
          map (x: x.to)
            (sc {
              items = [ { value = [ "b" ]; } ];
            }).derivedEdges
        );
    fromScan-project-result-item-without-id =
      refusal "fromScan"
        "project on a reference of the item at position 0 returned a int, not a node id (a string)"
        (builtins.head
          (sc {
            items = [ { value = [ "b" ]; } ];
            project = _: 1;
          }).derivedEdges
        ).to
        (builtins.head
          (sc {
            items = [ { value = [ "b" ]; } ];
          }).derivedEdges
        ).to;
    fromScan-parents-from-not-a-string =
      refusal "fromScan" "parents element 0: 'from' is a int, not a node identifier (a string)"
        ((sc { parents = [ (e 42 "a") ]; }).parent "a")
        ((sc { parents = [ (e "b" "a") ]; }).parent "a");
    # read through `edges`, where the unguarded read answered `[ ]` (a misread)
    fromRegistry-registry-not-a-set =
      refusal "fromRegistry" "registry is a list, not an attrset from a node identifier to its entry"
        (
          (G.fromRegistry {
            registry = [ ];
            edges = G.field "deps";
          }).edges
            "a"
        )
        (
          (G.fromRegistry {
            registry.a.deps = [ "b" ];
            edges = G.field "deps";
          }).edges
            "a"
        );
    labeledFrom-perLabel-not-a-set =
      refusal "labeledFrom"
        "perLabel is a list, not an attrset from a label to a function returning a list of node ids"
        (
          (G.labeledFrom {
            perLabel = [ ];
            nodes = [ ];
          }).labeledEdges
            "a"
        )
        (
          (G.labeledFrom {
            perLabel = { };
            nodes = [ ];
          }).labeledEdges
            "a"
        );
    field-name-not-a-string = refusal "field" "name is a int, not an attribute name (a string)" (G.field
      42
      "a"
      { }
    ) (G.field "deps" "a" { });
    fields-names-not-a-list = refusal "fields" "names is a int, not a list of attribute names" (G.fields
      1
      "a"
      { }
    ) (G.fields [ "deps" ] "a" { });
    fields-names-element-not-a-string =
      refusal "fields" "names element 0 is a int, not an attribute name (a string)"
        (G.fields [ 42 ] "a" { })
        (G.fields [ "deps" ] "a" { });
  };

  # ── WHAT THE CONSTRUCTION DOES NOT REFUSE ──
  # A read that never met the defect answers as before: the guards sit at the reads, never ahead.
  domain = {
    # the parent index never reads an edge's `from`
    edges-from-int-read-through-parent = (G.mkGraph { edges = [ (e 42 "b") ]; }).parent "b";
    # an item the scan finds nothing in keys no edge, so its id is never keyed
    scan-int-id-with-no-reference =
      (sc {
        items = [
          {
            id = 42;
            value = [ ];
          }
        ];
      }).nodes;
    # a scan that never forces its argument never read `value`
    scan-ignores-a-missing-value =
      (G.fromScan {
        items = [ { id = "a"; } ];
        scan = _: [ "b" ];
        project = r: r;
      }).nodes;
  };

  # ── THE UNKEYED ANSWERS, den-hoag-3w9e7's ──
  # An endpoint passed through without keying is not checked for type here: whether an int is a
  # node id there is 3w9e7's ruling. These pin today's answers, so the landing of that ruling reds
  # them and forces a deliberate re-pin rather than a silent drift.
  unkeyed = {
    mkGraph-edges-to-int = (G.mkGraph { edges = [ (e "a" 42) ]; }).edges "a";
    mkGraph-parents-to-int = (G.mkGraph { parents = [ (e "a" 42) ]; }).parent "a";
    fromScan-derived-from-int =
      map (x: x.from)
        (sc {
          items = [
            {
              id = 42;
              value = [ "b" ];
            }
          ];
        }).derivedEdges;
    fromRegistry-target-int =
      (G.fromRegistry {
        registry.a = { };
        edges = _: _: [ 42 ];
      }).edges
        "a";
  };
}
