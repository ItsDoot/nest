import std/unittest
import nest

type
  Foo = object
    value: string

test "Entity creation":
  var world = newWorld()
  let entity = world.spawn()
  let entity2 = world.spawn()
  check entity2.id() > entity.id()

test "Entity component lifecycle":
  type MyComponent = object
    value: string
  var world = newWorld()
  var entity = world.spawn()
  entity[MyComponent] = MyComponent(value: "hello")
  let myComponentId = world.component(MyComponent)
  check entity.has(MyComponent)
  check entity.has(myComponentId)
  check entity[MyComponent] == MyComponent(value: "hello")
  entity.remove(MyComponent)
  check not entity.has(MyComponent)
  check not entity.has(myComponentId)
  entity.destroy()
  check not entity.isAlive()

test "Resource component lifecycle":
  type MyResource = object
    value: string
  var world = newWorld()
  world[MyResource] = MyResource(value: "hello")
  check world[MyResource][MyResource].value == "hello"

test "Destroying an entity is idempotent":
  var world = newWorld()
  var entity = world.spawn()
  entity.destroy()
  check not entity.isAlive()
  entity.destroy() # Should not raise an error
  check not entity.isAlive()

test "Destroying a component entity raises":
  var world = newWorld()
  let cid = world.component(Foo)
  var entity = world[cid]
  expect ValueError:
    entity.destroy()

test "Destroying an earlier entity preserves later entities":
  var world = newWorld()
  var entity1 = world.spawn()
  var entity2 = world.spawn()
  entity1[Foo] = Foo(value: "hello")
  entity2[Foo] = Foo(value: "world")
  entity1.destroy()
  check entity2.isAlive()
  check entity2[Foo] == Foo(value: "world")

test "Invalid entity access raises":
  var world = newWorld()
  var entity = world.spawn()
  entity.destroy()
  expect ValueError:
    discard entity[Foo].value

test "Moving archetypes preserves other entities":
  var world = newWorld()
  var entity1 = world.spawn()
  var entity2 = world.spawn()
  entity1[Foo] = Foo(value: "hello")
  entity2[Foo] = Foo(value: "world")
  entity1.remove(Foo)
  check entity2.isAlive()
  check entity2[Foo] == Foo(value: "world")
