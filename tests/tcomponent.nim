import std/[importutils, unittest, tables]
import nest

type
  Foo = object
    value: string
  Bar = object
    value: string
  Tag = distinct Zst

test "Component registration is stable":
  var world = newWorld()
  let first = world.component(Foo)
  let second = world.component(Foo)
  check first == second

test "Adding components works independently of registration order":
  var world = newWorld()
  discard world.component(Foo)
  var entity = world.spawn()
  entity[Bar] = Bar(value: "world")
  entity[Foo] = Foo(value: "hello")
  check entity[Foo] == Foo(value: "hello")
  check entity[Bar] == Bar(value: "world")

test "Adding components preserves existing values":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: "hello")
  entity[Bar] = Bar(value: "world")
  check entity[Foo] == Foo(value: "hello")
  check entity[Bar] == Bar(value: "world")

test "Overwriting a component preserves other components and replaces its value":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: "hello")
  entity[Bar] = Bar(value: "world")
  entity[Foo] = Foo(value: "goodbye")
  check entity[Foo] == Foo(value: "goodbye")
  check entity[Bar] == Bar(value: "world")

test "Component can be mutated through mutable access":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: "hello")
  entity[Foo].value = "goodbye"
  check entity[Foo] == Foo(value: "goodbye")

test "Removing an absent component does not raise":
  var world = newWorld()
  var entity = world.spawn()
  check not entity.has(Foo)
  entity.remove(Foo)
  check not entity.has(Foo)

test "Invalid component access raises":
  var world = newWorld()
  var entity = world.spawn()
  expect ValueError:
    discard entity[Foo].value

test "Tag components can be added and removed":
  check sizeof(Tag) == 0
  var world = newWorld()
  var entity = world.spawn()
  entity.add(Tag)
  check entity.has(Tag)
  check entity[Tag] is Tag
  entity.remove(Tag)
  check not entity.has(Tag)
  entity[Tag] = default(Tag)
  check entity.has(Tag)
  entity.remove(Tag)
  check not entity.has(Tag)

test "Tag components are not stored in the archetype columns":
  privateAccess(World)
  privateAccess(Entities)
  privateAccess(EntityRecord)
  privateAccess(Archetype)
  var world = newWorld()
  var entity = world.spawn()
  entity.add(Tag)
  world.entities.records.withValue(entity.id, erecord):
    check erecord.archetype.columnMap[0] == -1
  do:
    assert false, "unexpected error: entity record not found"

test "add()ed components are their default values":
  var world = newWorld()
  var entity = world.spawn()
  entity.add(Foo)
  check entity[Foo] == Foo(value: "")

test "add()ing a component that's already added preserves its original value":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: "hello")
  entity.add(Foo)
  check entity[Foo] == Foo(value: "hello")
