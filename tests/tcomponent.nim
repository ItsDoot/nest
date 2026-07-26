import unittest
import nest

type
  Foo = object
    value: string
  Bar = object
    value: string

test "Component registration is stable":
  var world = newWorld()
  let first = world.component(Foo)
  let second = world.component(Foo)
  check first == second

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
