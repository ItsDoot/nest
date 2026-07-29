import std/[options, strformat, hashes]

type
  Keyable* = concept k, type K
    ## Anything that can be converted to and from a `Key`.
    compiles(Key(k))
    compiles(K(default(Key)))
  Key* = object
    ## A unique identifier for a slot in the `SlotMap`.
    index*: uint32
      ## The index of the slot in the `slots` array.
    version*: uint32
      ## The generation of the slot, used to detect stale references.
      ## If the version is 0, the slot has never been used.
  Slot[V] = object
    ## A versioned, maybe-occupied entry in the `SlotMap`.
    version: uint32
      ## The generation of the slot, used to detect stale references.
      ## If the version is 0, the slot has never been used.
    value: Option[V]
      ## The value stored in the slot. If the slot is free, this field is undefined.
  SlotMap*[K: Keyable, V] = object
    ## A dense, versioned map.
    slots: seq[Slot[V]]
      ## The array of slots, where each slot can either be occupied or free.
    freeList: seq[uint32]
      ## A list of indices of free slots in the `slots` array. Allows for
      ## efficient reuse of slots.
  VersionCheck* = enum
    vcOn
    vcOff

func `==`*(a, b: Key): bool =
  ## Compares two keys for equality based on their index and version.
  result = a.index == b.index and a.version == b.version

func `>`*(a, b: Key): bool =
  ## Compares two keys based on their index and version.
  result = a.index > b.index or (a.index == b.index and a.version > b.version)

func `<`*(a, b: Key): bool =
  ## Compares two keys based on their index and version.
  result = a.index < b.index or (a.index == b.index and a.version < b.version)

func `$`*(key: Key): string =
  ## Returns a string representation of the key in the format "index:version".
  result = &"{key.index}v{key.version}"

func hash*(key: Key): Hash =
  ## Computes a hash value for the key by combining its index and version.
  result = Hash((key.index shl 32) or key.version)

converter toUint64*(key: Key): uint64 =
  ## Converts a `Key` to a `uint64` by packing the index and version into a single integer.
  result = (uint64(key.version) shl 32) or uint64(key.index)

proc contains*[K: Keyable, V](sm: SlotMap[K, V], key: K): bool =
  ## Checks if the given key is valid and the slot is occupied in the `SlotMap`.
  let key = Key(key)
  if key.index >= uint32(sm.slots.len):
    return false
  let slot = sm.slots[key.index]
  result = slot.version == key.version and slot.value.isSome

proc checkLent[V](slot: lent Slot[V], version: uint32, versionCheck: static VersionCheck): lent V =
  ## Returns the value of the slot if it is valid and occupied, otherwise raises an exception.
  if versionCheck == vcOn and slot.version != version:
    raise newException(ValueError, "Invalid key: version mismatch")
  if slot.value.isNone:
    raise newException(ValueError, "Slot is free: no value associated with the key")
  result = slot.value.get()

proc `[]`*[K: Keyable, V](sm: SlotMap[K, V], key: K, versionCheck: static VersionCheck = vcOn): lent V =
  ## Returns the value associated with the given key if it exists and is valid.
  ## If the key is invalid or the slot is free, it returns `none`.
  let key = Key(key)
  if key.index >= uint32(sm.slots.len):
    raise newException(ValueError, "Invalid key: index out of bounds")
  result = checkLent(sm.slots[key.index], key.version, versionCheck)

proc checkVar[V](slot: var Slot[V], version: uint32, versionCheck: static VersionCheck): var V =
  ## Returns a mutable reference to the value of the slot if it is valid and occupied, otherwise raises an exception.
  if versionCheck == vcOn and slot.version != version:
    raise newException(ValueError, "Invalid key: version mismatch")
  if slot.value.isNone:
    raise newException(ValueError, "Slot is free: no value associated with the key")
  result = slot.value.get()

proc `[]`*[K: Keyable, V](sm: var SlotMap[K, V], key: K, versionCheck: static VersionCheck = vcOn): var V =
  ## Returns a mutable reference to the value associated with the given key if it exists and is valid.
  ## If the key is invalid or the slot is free, it raises an exception.
  let key = Key(key)
  if key.index >= uint32(sm.slots.len):
    raise newException(ValueError, "Invalid key: index out of bounds")
  result = checkVar(sm.slots[key.index], key.version, versionCheck)

proc add*[K: Keyable, V](sm: var SlotMap[K, V], value: V): K =
  ## Adds a new value to the `SlotMap` and returns a key that can be used to
  ## access it. If there are free slots available, it reuses one of them;
  ## otherwise, it appends a new slot to the `slots` array.
  var index: uint32
  if sm.freeList.len > 0:
    index = sm.freeList.pop()
    sm.slots[index].value = some(value)
  else:
    if sm.slots.len >= int(high(uint32)):
      raise newException(ValueError, "SlotMap has reached its maximum capacity")
    index = uint32(sm.slots.len)
    sm.slots.add(Slot[V](version: 1, value: some(value)))
  result = K(Key(index: index, version: sm.slots[index].version))

proc remove[V](slot: var Slot[V], version: uint32, versionCheck: static VersionCheck = vcOn): Option[V] =
  ## Removes the value from the slot and returns it. If the slot is free,
  ## it returns `none`.
  if versionCheck == vcOn and slot.version != version:
    result = none(V)
  elif slot.value.isNone:
    result = none(V)
  else:
    result = slot.value
    slot.value = none(V)
    slot.version.inc()

proc remove*[K: Keyable, V](sm: var SlotMap[K, V], key: K, versionCheck: static VersionCheck = vcOn): Option[V] =
  ## Removes the value associated with the given key from the `SlotMap`.
  ## If the key is valid and the slot is occupied, it returns the value and
  ## marks the slot as free. Otherwise, it returns `none`.
  let key = Key(key)
  if key.index >= uint32(sm.slots.len):
    result = none(V)
    return
  result = sm.slots[key.index].remove(key.version, versionCheck)
  if result.isSome:
    sm.freeList.add(key.index)

proc valuePtr[K: Keyable, V](sm: var SlotMap[K, V], key: K): ptr V =
  ## Returns a pointer to the value associated with the given key if it exists
  ## and is valid. Otherwise returns nil.
  let key = Key(key)
  if key.index >= uint32(sm.slots.len):
    return nil
  let slot = addr sm.slots[key.index]
  if slot[].version != key.version or slot[].value.isNone:
    return nil
  result = addr slot[].value.get()

template withValue*[K: Keyable, V](sm: var SlotMap[K, V], key: K, value, present, absent: untyped): untyped =
  let value {.inject.} = valuePtr(sm, key)
  if value != nil:
    present
  else:
    absent

template withValue*[K: Keyable, V](sm: var SlotMap[K, V], key: K, value, present: untyped): untyped =
  let value {.inject.} = valuePtr(sm, key)
  if value != nil:
    present
