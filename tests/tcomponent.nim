import unittest
import nest

type
  Foo = object
    value: int
  Bar = object
    value: int

test "Component registration is stable":
  var world = newWorld()
  let first = world.component(Foo)
  let second = world.component(Foo)
  check first == second

test "Adding components preserves existing values":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: 42)
  entity[Bar] = Bar(value: 99)
  check entity[Foo] == Foo(value: 42)
  check entity[Bar] == Bar(value: 99)

test "Overwriting a component preserves other components and replaces its value":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: 42)
  entity[Bar] = Bar(value: 99)
  entity[Foo] = Foo(value: 100)
  check entity[Foo] == Foo(value: 100)
  check entity[Bar] == Bar(value: 99)

test "Component can be mutated through mutable access":
  var world = newWorld()
  var entity = world.spawn()
  entity[Foo] = Foo(value: 42)
  entity[Foo].value = 100
  check entity[Foo] == Foo(value: 100)

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
