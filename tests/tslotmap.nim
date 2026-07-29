import std/[unittest, options]
import nest/slotmap

type MyKey = distinct Key

test "Added values can be accessed":
  var map: SlotMap[MyKey, string]
  let key = map.add("hello")
  check key in map
  check map[key] == "hello"

test "Values can be mutated":
  var map: SlotMap[MyKey, int]
  let key = map.add(42)
  check map[key] == 42
  map[key] = 100
  check map[key] == 100

test "Multiple values can be added and accessed":
  var map: SlotMap[MyKey, int]
  let key1 = map.add(1)
  let key2 = map.add(2)
  let key3 = map.add(3)
  check map[key1] == 1
  check map[key2] == 2
  check map[key3] == 3

test "Removing a value returns it and invalidates the key":
  var map: SlotMap[MyKey, string]
  let key = map.add("to be removed")
  let removedValue = map.remove(key)
  check removedValue.isSome
  check removedValue.get() == "to be removed"
  check not (key in map)

test "Removing the same key twice returns none the second time":
  var map: SlotMap[MyKey, string]
  let key = map.add("to be removed")
  let removedValue1 = map.remove(key)
  let removedValue2 = map.remove(key)
  check removedValue1.isSome
  check removedValue1.get() == "to be removed"
  check removedValue2.isNone

test "Removing an OOB key returns none":
  var map: SlotMap[MyKey, string]
  let key = MyKey(Key(index: 999, version: 1))
  let removedValue = map.remove(key)
  check removedValue.isNone

test "Accessing an OOB key raises":
  var map: SlotMap[MyKey, string]
  let key = MyKey(Key(index: 999, version: 1))
  expect ValueError:
    discard map[key]

test "Freed slots are reused":
  var map: SlotMap[MyKey, string]
  let key1 = map.add("first")
  let key2 = map.add("second")
  let removedValue = map.remove(key1)
  check removedValue.isSome
  check removedValue.get() == "first"
  let key3 = map.add("third")
  check Key(key3).index == Key(key1).index
  check Key(key3).version != Key(key1).version
  check map[key3] == "third"

test "Stale keys cannot access newer values":
  var map: SlotMap[MyKey, string]
  let key1 = map.add("first")
  let removedValue = map.remove(key1)
  check removedValue.isSome
  check removedValue.get() == "first"
  let key2 = map.add("second")
  expect ValueError:
    discard map[key1]

test "Stale keys cannot remove newer values":
  var map: SlotMap[MyKey, string]
  let key1 = map.add("first")
  let removedValue = map.remove(key1)
  check removedValue.isSome
  check removedValue.get() == "first"
  let key2 = map.add("second")
  let removedValue2 = map.remove(key1)
  check removedValue2.isNone

test "Version checks can be explicitly disabled":
  var map: SlotMap[MyKey, string]
  let key1 = map.add("first")
  let removedValue = map.remove(key1)
  check removedValue.isSome
  check removedValue.get() == "first"
  let key2 = map.add("second")
  check map[key1, vcOff] == "second"
  map[key1, vcOff] = "modified"
  check map[key2] == "modified"
