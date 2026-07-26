import std/[tables, algorithm, options]
import blobseq

##################################################
# TYPE DEFINITIONS
##################################################

type
  Zst* = array[0, byte]
    ## A zero-sized type (ZST) with no associated data. You can use this to
    ## create tag components in the ECS world:
    ## 
    ## ```nim
    ## type MyTag = distinct Zst
    ## ```

  TypeId* = distinct uint32
    ## Unique identifier for a type.

  EntityId* = distinct uint32
    ## Unique identifier for an entity.

  Id* = distinct uint32
    ## Unique identifier for anything that can be added to an entity, including
    ## components and tags.

  ArchetypeId* = distinct uint32
    ## Unique identifier for an archetype.

  Signature* = seq[Id]
    ## A sorted list of identifiers that make up an archetype.

  Column* = BlobSeq
    ## A homogenous collection of components of a specific type in an archetype.

  Archetype* = ref object
    ## A unique combination of components in the ECS world.
    id: ArchetypeId
      ## Unique identifier for the archetype.
    signature: Signature
      ## A sorted list of component IDs that make up the archetype.
    columnMap: seq[int]
      ## A mapping of component ID indices to their corresponding column indices
      ## in the archetype. Sorted in the same order as `signature`. Values of -1
      ## indicate that the component is a tag (i.e., it has no associated data).
    columns: seq[Column]
      ## A collection of columns, each representing a specific component type in the archetype.
    entities: seq[EntityId]
      ## A collection of entity IDs that belong to the archetype.
    edges: Table[Id, ArchetypeEdge]
      ## A mapping of identifiers to their corresponding archetype edges.

  ArchetypeEdge* = object
    ## The transition from one archetype to another when adding or removing a component.
    add: Archetype
    remove: Archetype

  Archetypes* = object
    nextId: ArchetypeId
      ## The next available archetype ID.
    table: Table[Signature, Archetype]
      ## A mapping of signatures to their corresponding archetypes.
    empty: Archetype
      ## The archetype that represents an empty signature (i.e., no components).

  ArchetypeRecord* = object
    ## A record in the component index with the component column for an archetype.
    column: int
      ## The index of the component column in the archetype's columns.

  EntityRecord* = object
    ## A record that stores the archetype and row index for an entity.
    archetype: Archetype
      ## The archetype to which the entity belongs.
    row: int
      ## The row index of the entity in the archetype's columns.

  Entities* = object
    nextId: EntityId
      ## The next available entity ID.
    records: Table[EntityId, EntityRecord]
      ## A mapping of entity IDs to their corresponding entity records.

  IdRecord* = object
    ## A record that stores the archetypes that contain its component or tag.
    archetypes: Table[ArchetypeId, ArchetypeRecord]

  Components* = object
    ## A collection of all components in the ECS world.
    types: Table[TypeId, EntityId]
      ## A mapping of type IDs to their corresponding component IDs.

  World* = ref object
    ## The ECS world that manages entities and archetypes.
    archetypes: Archetypes
      ## A collection of all archetypes in the ECS world.
    entities: Entities
      ## A collection of all entities in the ECS world.
    ids: Table[Id, IdRecord]
      ## A mapping of IDs to their corresponding ID records.
    types: Table[TypeId, EntityId]
      ## A mapping of type IDs to their corresponding entity IDs.

  Entity* = object
    ## A handle to an entity in the ECS world.
    world: World
      ## The ECS world to which the entity belongs.
    id: EntityId
      ## The unique identifier of the entity.

  Component* = object
    ## A component that stores the TypeInfo of a component type.
    info: TypeInfo
      ## The TypeInfo object that describes the component type.

##################################################
# ID MANAGEMENT
##################################################

proc `==`*(a, b: TypeId): bool {.borrow.}
proc `<`*(a, b: TypeId): bool {.borrow.}

proc `==`*(a, b: EntityId): bool {.borrow.}
proc `<`*(a, b: EntityId): bool {.borrow.}
proc `$`*(a: EntityId): string {.borrow.}

proc `==`*(a, b: Id): bool {.borrow.}
proc `<`*(a, b: Id): bool {.borrow.}
proc `$`*(a: Id): string {.borrow.}

converter toId*(a: EntityId): Id =
  result = Id(uint32(a))

proc `==`*(a, b: ArchetypeId): bool {.borrow.}

var nextTypeId: uint32 = 0

proc typeId*[T](): TypeId =
  ## Returns a unique type ID for the specified type T.
  var id {.global.} = block:
    let newId = nextTypeId
    nextTypeId.inc()
    TypeId(newId)
  result = id

##################################################
# ARCHETYPE MANAGEMENT
##################################################

proc nextArchetypeId(archetypes: var Archetypes): ArchetypeId =
  ## Returns the next available archetype ID and increments the counter.
  let id = archetypes.nextId
  archetypes.nextId.inc()
  result = id

proc getComponentId[T](world: World, cType: typedesc[T]): EntityId =
  ## Retrieves the entity ID associated with the given type ID.
  let id = typeId[T]()
  world.types.withValue(id, val):
    return val[]
  do:
    raise newException(ValueError, "Component type ID " & $T & " is not registered")

template fetch(world: World, eid: EntityId, cid: Id, found: untyped, missing: untyped): untyped =
  ## Fetches the various records associated with the given entity ID and ecs ID,
  ## and executes the provided body with those records in scope.
  world.entities.records.withValue(eid, erecord):
    world.ids.withValue(cid, irecord):
      found
    do:
      missing
  do:
    var irecord {.inject.}: ptr IdRecord = nil
    missing

template fetchPointer(world: World, eid: EntityId, cid: Id): pointer =
  ## Fetches the various records associated with the given entity ID and ecs ID,
  ## and returns a pointer to the component data of the specified ID in the given entity.
  fetch(world, eid, cid):
    irecord.archetypes.withValue(erecord.archetype.id, val):
      if val.column == -1:
        return nil # Tag component, no data
      let column = erecord.archetype.columns[val.column]
      return column[erecord.row]
  do:
    return nil

template fetchTyped[T](world: World, eid: EntityId, cid: Id) =
  ## Fetches the various records associated with the given entity ID and ecs ID,
  ## and returns a reference to the component data of type T in the given entity.
  fetch(world, eid, cid):
    irecord.archetypes.withValue(erecord.archetype.id, arecord):
      if arecord.column == -1:
        raise newException(ValueError, "Component of type " & $T & " is a tag and has no associated data")
      result = erecord.archetype.columns[arecord.column][erecord.row, T]
    do:
      raise newException(ValueError, "Entity does not have component of type " & $T)
  do:
    raise newException(ValueError, "Entity does not have component of type " & $T)

template fetchTyped[T](world: World, eid: EntityId, cType: typedesc[T]) =
  ## Fetches the various records associated with the given entity ID and component type,
  ## and returns a reference to the component data of type T in the given entity.
  let cid = world.getComponentId(T)
  fetchTyped[T](world, eid, cid)

proc getTypeInfo(world: World, id: Id): Option[TypeInfo] =
  ## Determines if the component or tag with the given ID requires storage.
  let eid = EntityId(uint32(id))
  let cid = world.getComponentId(Component)
  world.entities.records.withValue(eid, erecord):
    world.ids.withValue(cid, irecord):
      irecord.archetypes.withValue(erecord.archetype.id, val):
        if val.column == -1:
          raise newException(ValueError, "ID corresponds to a tag (no Component component data)")
        return some(erecord.archetype.columns[val.column][erecord.row, Component].info)
      do:
        return none(TypeInfo) # The ID corresponds to a tag (no Component component)
    do:
      raise newException(ValueError, "'Component' does not exist in the world")
  do:
    return none(TypeInfo) # The ID does not correspond to a valid entity in the world

proc getOrCreateArchetype(world: var World, sig: sink Signature): Archetype =
  ## Retrieves an existing archetype with the specified signature or creates a
  ## new one if it doesn't exist.
  assert sig.isSorted, "Signature must be sorted"

  result = world.archetypes.table.getOrDefault(sig)
  if result != nil:
    return result

  let newId = world.archetypes.nextArchetypeId()

  var columnMap = newSeq[int](sig.len)
  var columns = newSeq[Column]()
  for i, id in sig:
    world.ids.withValue(id, irecord):
      let typeInfo = world.getTypeInfo(id)
      if typeInfo.isNone or typeInfo.get().size == 0:
        columnMap[i] = -1 # Tag component, no data
        irecord.archetypes[newId] = ArchetypeRecord(column: -1)
      else:
        columnMap[i] = columns.len
        columns.add(initBlobSeq(typeInfo.get()))
        irecord.archetypes[newId] = ArchetypeRecord(column: columnMap[i])
    do:
      assert false, "Component entity with ID " & $id & " does not exist in the world"

  result = Archetype(
    id: newId,
    signature: sig,
    columnMap: columnMap,
    columns: columns,
    edges: initTable[Id, ArchetypeEdge]()
  )
  world.archetypes.table[sig] = result

proc swapRemoveEntity(world: var World, archetype: Archetype, row: int) =
  ## Removes the entity at the specified row from the archetype, swapping it
  ## with the last entity in the archetype.
  let lastRow = archetype.entities.len - 1
  if row != lastRow:
    let lastEntityId = archetype.entities[lastRow]
    world.entities.records[lastEntityId].row = row
    archetype.entities[row] = lastEntityId
  archetype.entities.setLen(lastRow)

proc moveEntity(world: var World, id: EntityId, dst: Archetype): int =
  ## Moves an entity to a new archetype, updating its record and transferring its components.
  ## Returns the new row index of the entity in the destination archetype.
  world.entities.records.withValue(id, record):
    let src = record.archetype
    let oldRow = record.row
    let newRow = dst.entities.len
    dst.entities.add(id)

    var srcIdx = 0
    var dstIdx = 0

    while srcIdx < src.signature.len and dstIdx < dst.signature.len:
      let srcCid = src.signature[srcIdx]
      let dstCid = dst.signature[dstIdx]
      let srcCol = src.columnMap[srcIdx]
      let dstCol = dst.columnMap[dstIdx]

      # TODO: optimize with supportsCopyMem
      if srcCid == dstCid:
        # Component exists in both archetypes, transfer it
        if srcCol != -1 and dstCol != -1:
          dst.columns[dstCol].transferItem(src.columns[srcCol], oldRow)
        else:
          assert srcCol == -1 and dstCol == -1, "Tag component should not have data"
        srcIdx.inc()
        dstIdx.inc()
      elif srcCid < dstCid:
        # Component exists only in source archetype, remove it
        if srcCol != -1:
          src.columns[srcCol].swapRemove(oldRow)
        srcIdx.inc()
      else:
        # Component exists only in destination archetype, add default value
        if dstCol != -1:
          dst.columns[dstCol].addDefault()
        dstIdx.inc()

    while srcIdx < src.signature.len:
      # Remove remaining components from source archetype
      let srcCol = src.columnMap[srcIdx]
      if srcCol != -1:
        src.columns[srcCol].swapRemove(oldRow)
      srcIdx.inc()
    
    while dstIdx < dst.signature.len:
      # Add default values for remaining components in destination archetype
      let dstCol = dst.columnMap[dstIdx]
      if dstCol != -1:
        dst.columns[dstCol].addDefault()
      dstIdx.inc()

    world.swapRemoveEntity(src, oldRow)
    record.archetype = dst
    record.row = newRow
    return newRow
  do:
    raise newException(ValueError, "Entity with ID " & $id & " does not exist in the world")

type Operation = enum
  opAdd, opRemove

proc getOrCreateEdge(world: var World, src: Archetype, id: Id, op: static[Operation]): Archetype =
  ## Retrieves an existing archetype edge for the specified component ID and operation
  ## or creates a new one if it doesn't exist.
  let edge = src.edges.getOrDefault(id)
  result = case op
    of opAdd: edge.add
    of opRemove: edge.remove
  if result != nil:
    return result
  
  var newSig = src.signature
  case op
    of opAdd: newSig.insert(id, newSig.lowerBound(id))
    of opRemove: newSig.delete(newSig.binarySearch(id))
  result = world.getOrCreateArchetype(newSig)

  case op
    of opAdd:
      src.edges[id] = ArchetypeEdge(add: result, remove: edge.remove)
      result.edges.mgetOrPut(id, ArchetypeEdge()).remove = src
    of opRemove:
      src.edges[id] = ArchetypeEdge(add: edge.add, remove: result)
      result.edges.mgetOrPut(id, ArchetypeEdge()).add = src

##################################################
# ENTITY MANAGEMENT
##################################################

proc `[]`*(world: World, id: EntityId): Entity =
  ## Retrieves an entity handle from the ECS world given its unique identifier.
  if id notin world.entities.records:
    raise newException(ValueError, "Entity with ID " & $id & " does not exist in the world")
  result = Entity(world: world, id: id)

proc `[]`*[T](world: World, cType: typedesc[T]): Entity =
  ## Retrieves an entity handle for the component type T from the ECS world.
  let cid = world.getComponentId(T)
  result = world[cid]

proc `[]=`*[T](world: var World, cType: typedesc[T], value: sink T) =
  ## Inserts a resource of type T into the ECS world, placing it on its own entity.
  let eid = world.component(T)
  var entity = world[eid]
  entity[T] = value

proc spawn*(world: var World): Entity =
  ## Creates a new entity in the ECS world and returns its handle.
  let id = world.entities.nextId
  world.entities.nextId.inc()

  let emptyArchetype = world.archetypes.empty
  let row = emptyArchetype.entities.len
  emptyArchetype.entities.add(id)

  world.entities.records[id] = EntityRecord(archetype: emptyArchetype, row: row)
  result = Entity(world: world, id: id)

proc component*[T](world: var World, cType: typedesc[T]): EntityId =
  ## Registers a new component type T in the ECS world and returns its unique entity ID.
  let tid = typeId[T]()
  world.types.withValue(tid, val):
    return val[] # component type already registered, return existing ID
  var entity = world.spawn()
  world.ids[entity.id] = IdRecord()
  world.types[tid] = entity.id
  entity[Component] = Component(info: newTypeInfo[T]())
  result = entity.id

proc id*(entity: Entity): EntityId =
  ## Returns the unique identifier of the entity.
  result = entity.id

proc isAlive*(entity: Entity): bool =
  ## Checks if the entity is alive in the ECS world.
  let world = entity.world
  result = entity.id in world.entities.records

proc has*(entity: Entity, id: Id): bool =
  ## Checks if this entity has the component or tag with the given ID.
  let world = entity.world
  world.fetch(entity.id, id):
    return erecord.archetype.id in irecord.archetypes
  do:
    return false # The entity does not have the component or tag with the given ID

proc has*[T](entity: Entity, cType: typedesc[T]): bool =
  ## Checks if the entity has a component of type T.
  let world = entity.world
  world.types.withValue(typeId[T](), val):
    let cid = val[]
    return entity.has(cid)
  do:
    return false # Component type T is not registered

proc `[]`*[T](entity: Entity, cType: typedesc[T]): lent T =
  ## Retrieves the component of type T associated with the entity, if it exists.
  fetchTyped[T](entity.world, entity.id, cType)

proc `[]`*[T](entity: var Entity, cType: typedesc[T]): var T =
  ## Retrieves the component of type T associated with the entity, if it exists.
  fetchTyped[T](entity.world, entity.id, cType)

proc `[]=`*[T](entity: var Entity, cType: typedesc[T], value: sink T) =
  ## Associates a component of type T with the entity.
  var world = entity.world
  var erecord = world.entities.records[entity.id]
  let cid = world.component(T)

  world.ids.withValue(cid, irecord):
    irecord.archetypes.withValue(erecord.archetype.id, val):
      # component already present, overwrite it
      if val.column != -1:
        erecord.archetype.columns[val.column][erecord.row, T] = value
      return

    # need to move entity to a new archetype
    let dest = world.getOrCreateEdge(erecord.archetype, cid, opAdd)
    let newRow = world.moveEntity(entity.id, dest)
    let newColumn = irecord.archetypes[dest.id].column
    if newColumn != -1:
      dest.columns[newColumn][newRow, T] = value

proc add*(entity: var Entity, id: Id) =
  ## Adds the given ID to the entity. If the ID corresponds to a tag
  ## (a zero-sized component), it will be added without any associated data.
  ## Otherwise, the component will be initialized with its default value.
  var world = entity.world
  var erecord = world.entities.records[entity.id]
  world.ids.withValue(id, irecord):
    if irecord.archetypes.hasKey(erecord.archetype.id):
      # component already present, do nothing
      return

    # need to move entity to a new archetype
    let dest = world.getOrCreateEdge(erecord.archetype, id, opAdd)
    discard world.moveEntity(entity.id, dest)

proc add*[T](entity: var Entity, cType: typedesc[T]) =
  ## Adds a component of type T to the entity. If the component is zero-sized
  ## (i.e., a tag), it will be added without any associated data. Otherwise,
  ## the component will be initialized with its default value.
  let cid = entity.world.component(T)
  entity.add(cid)

proc remove*(entity: var Entity, id: Id) =
  ## Removes the component or tag with the given ID from the entity, if it exists.
  var world = entity.world
  var erecord = world.entities.records[entity.id]
  world.ids.withValue(id, irecord):
    if not irecord.archetypes.hasKey(erecord.archetype.id):
      return # entity doesn't have the component
    
    # need to move entity to a new archetype
    let dest = world.getOrCreateEdge(erecord.archetype, id, opRemove)
    discard world.moveEntity(entity.id, dest)
  do:
    return # ID is not registered, nothing to remove

proc remove*[T](entity: var Entity, cType: typedesc[T]) =
  ## Removes the component of type T from the entity, if it exists.
  let cid = entity.world.component(T)
  entity.remove(cid)

proc destroy*(entity: sink Entity) =
  ## Destroys the entity and removes it from the ECS world.
  if not entity.isAlive():
    return

  if entity.has(Component):
    raise newException(ValueError, "Cannot destroy component entities")

  let record = entity.world.entities.records[entity.id]

  for col in record.archetype.columns.mitems:
    col.swapRemove(record.row)
  
  entity.world.swapRemoveEntity(record.archetype, record.row)
  entity.world.entities.records.del(entity.id)

##################################################
# WORLD MANAGEMENT
##################################################

proc bootstrap(world: var World) =
  ## Bootstraps the ECS world by seeding the archetype that holds `Component` entities.
  world.archetypes.empty = world.getOrCreateArchetype(@[])
  let tid = typeId[Component]()
  var entity = world.spawn()
  world.types[tid] = entity.id

  let sig = @[Id(entity.id)]
  let newId = world.archetypes.nextArchetypeId()
  world.ids.mgetOrPut(entity.id, IdRecord()).archetypes[newId] = ArchetypeRecord(column: 0)
  let archetype = Archetype(
    id: newId,
    signature: sig,
    columnMap: @[0],
    columns: @[initBlobSeq(newTypeInfo[Component]())],
    edges: initTable[Id, ArchetypeEdge]()
  )
  world.archetypes.table[sig] = archetype

  let newRow = world.moveEntity(entity.id, archetype)
  archetype.columns[0][newRow, Component] = Component(info: newTypeInfo[Component]())

proc newWorld*(): World =
  result = World()
  result.bootstrap()
