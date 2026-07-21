# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import nest

test "Entity creation":
  var world = newWorld()
  let entity = world.spawn()
  check entity.id() == EntityId(0)
  let entity2 = world.spawn()
  check entity2.id() == EntityId(1)

test "Entity component lifecycle":
  type MyComponent = object
    value: int

  var world = newWorld()
  var entity = world.spawn()
  entity[MyComponent] = MyComponent(value: 42)
  check entity[MyComponent] == MyComponent(value: 42)
  entity.remove(MyComponent)
  check not entity.has(MyComponent)

  entity.destroy()
  check not entity.isAlive()
