import std/unittest
import nest

type Foo = object
  value: string
type Bar = object
  value: seq[int]
type BazTag = distinct nest.Zst

test "Query returns all entities with a component":
  var world = newWorld()
  var entity1 = world.spawn()
  var entity2 = world.spawn()
  entity1[Foo] = Foo(value: "hello")
  entity2[Foo] = Foo(value: "world")
  var results = newSeq[(EntityId, Foo)]()
  for (id, foo) in world.query(Foo):
    results.add((id, foo))
  check results.len == 2
  check (results[0][1].value == "hello" and results[1][1].value == "world") or
        (results[0][1].value == "world" and results[1][1].value == "hello")

test "Query returns non-nil ptrs for tags":
  var world = newWorld()
  var entity1 = world.spawn()
  var entity2 = world.spawn()
  entity1.add(BazTag)
  entity2.add(BazTag)
  var results = newSeq[EntityId]()
  for (id, baz) in world.query(BazTag):
    results.add(id)
  check results.len == 2

test "Query returns all entities with 2 components":
  var world = newWorld()
  var entity1 = world.spawn()
  var entity2 = world.spawn()
  entity1[Foo] = Foo(value: "hello")
  entity1.add(BazTag)
  entity2[Foo] = Foo(value: "world")
  entity2.add(BazTag)
  var results = newSeq[(EntityId, Foo, BazTag)]()
  for (id, foo, baz) in world.query(Foo, BazTag):
    results.add((id, foo, baz))
  check results.len == 2
  check (results[0][1].value == "hello" and results[1][1].value == "world") or
        (results[0][1].value == "world" and results[1][1].value == "hello")

test "Query returns all entities with 3 components":
  var world = newWorld()
  var entity1 = world.spawn()
  var entity2 = world.spawn()
  entity1[Foo] = Foo(value: "hello")
  entity1.add(BazTag)
  entity1[Bar] = Bar(value: @[1, 2, 3])
  entity2[Foo] = Foo(value: "world")
  entity2.add(BazTag)
  entity2[Bar] = Bar(value: @[4, 5, 6])
  var results = newSeq[(EntityId, Foo, BazTag, Bar)]()
  for (id, foo, baz, bar) in world.query(Foo, BazTag, Bar):
    results.add((id, foo, baz, bar))
  check results.len == 2
  check (results[0][1].value == "hello" and results[1][1].value == "world") or
        (results[0][1].value == "world" and results[1][1].value == "hello")