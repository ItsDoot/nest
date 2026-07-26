import std/[tables, algorithm]
import blobseq

##################################################
# TYPE DEFINITIONS
##################################################

type
  TypeId* = distinct uint32
    ## Unique identifier for a type.

  EntityId* = distinct uint32
    ## Unique identifier for an entity.
  
  ArchetypeId* = distinct uint32
    ## Unique identifier for an archetype.
  
  Signature* = seq[EntityId]
    ## A sorted list of entity IDs that make up an archetype.
  
  Column* = BlobSeq
    ## A homogenous collection of components of a specific type in an archetype.

  Archetype* = ref object
    ## A unique combination of components in the ECS world.
    id: ArchetypeId
      ## Unique identifier for the archetype.
    signature: Signature
      ## A sorted list of component IDs that make up the archetype.
    columns: seq[Column]
      ## A collection of columns, each representing a specific component type in the archetype.
    entities: seq[EntityId]
      ## A collection of entity IDs that belong to the archetype.
    edges: Table[EntityId, ArchetypeEdge]
      ## A mapping of component IDs to their corresponding archetype edges.
  
  ArchetypeEdge* = object
    ## The transition from one archetype to another when adding or removing a component.
    add: Archetype
    remove: Archetype

  Archetypes* = object
    nextId: ArchetypeId
      ## The next available archetype ID.
    table: Table[Signature, Archetype]
      ## A mapping of signatures to their corresponding archetypes.

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
    archetypes: Table[ArchetypeId, ArchetypeRecord]
      ## A mapping of archetype IDs to their corresponding archetype records.
      ## Nil if the entity is not a component entity.

  Entities* = object
    nextId: EntityId
      ## The next available entity ID.
    records: Table[EntityId, EntityRecord]
      ## A mapping of entity IDs to their corresponding entity records.

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
    components: Components
      ## A collection of all components in the ECS world.
  
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
  ## Retrieves the component ID associated with the given type ID.
  let id = typeId[T]()
  world.components.types.withValue(id, val):
    return val[]
  do:
    raise newException(ValueError, "Component type ID " & $T & " is not registered")

proc tryGetColumn(world: World, record: EntityRecord, cid: EntityId): int =
  ## Returns the column index of a component in the given entity's archetype,
  ## or -1 if the component is not present.
  let componentRecord = world.entities.records.getOrDefault(cid)
  componentRecord.archetypes.withValue(record.archetype.id, val):
    return val.column
  do:
    return -1

proc getTypeInfo(world: World, record: EntityRecord): TypeInfo =
  ## Retrieves the TypeInfo of a component from the given component entity's record.
  let componentCId = world.getComponentId(Component)
  let column = world.tryGetColumn(record, componentCId)
  if column == -1:
    raise newException(ValueError, "Entity is not a component entity")
  result = record.archetype.columns[column][record.row, Component].info

proc getOrCreateArchetype(world: var World, sig: sink Signature): Archetype =
  ## Retrieves an existing archetype with the specified signature or creates a
  ## new one if it doesn't exist.
  assert sig.isSorted, "Signature must be sorted"

  result = world.archetypes.table.getOrDefault(sig)
  if result != nil:
    return result

  let newId = world.archetypes.nextArchetypeId()

  var columns = newSeq[Column](sig.len)
  for i, cid in sig:
    columns[i] = initBlobSeq(world.getTypeInfo(world.entities.records[cid]))
    world.entities.records[cid].archetypes[newId] = ArchetypeRecord(column: i)

  result = Archetype(
    id: newId,
    signature: sig,
    columns: columns,
    edges: initTable[EntityId, ArchetypeEdge]()
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

proc moveEntity(world: var World, id: EntityId, dst: Archetype) =
  ## Moves an entity to a new archetype, updating its record and transferring its components.
  world.entities.records.withValue(id, record):
    let src = record.archetype
    let oldRow = record.row
    let newRow = dst.entities.len
    dst.entities.add(id)

    var srcCol = 0
    var dstCol = 0

    while srcCol < src.signature.len and dstCol < dst.signature.len:
      let srcCid = src.signature[srcCol]
      let dstCid = dst.signature[dstCol]

      # TODO: optimize with supportsCopyMem
      if srcCid == dstCid:
        # Component exists in both archetypes, transfer it
        dst.columns[dstCol].transferItem(src.columns[srcCol], oldRow)
        srcCol.inc()
        dstCol.inc()
      elif srcCid < dstCid:
        # Component exists only in source archetype, remove it
        src.columns[srcCol].swapRemove(oldRow)
        srcCol.inc()
      else:
        # Component exists only in destination archetype, add default value
        dst.columns[dstCol].addDefault()
        dstCol.inc()

    while srcCol < src.signature.len:
      # Remove remaining components from source archetype
      src.columns[srcCol].swapRemove(oldRow)
      srcCol.inc()

    world.swapRemoveEntity(src, oldRow)
    record.archetype = dst
    record.row = newRow

type Operation = enum
  opAdd, opRemove

proc getOrCreateEdge(world: var World, src: Archetype, cid: EntityId, op: static[Operation]): Archetype =
  ## Retrieves an existing archetype edge for the specified component ID and operation
  ## or creates a new one if it doesn't exist.
  let edge = src.edges.getOrDefault(cid)
  result = case op
    of opAdd: edge.add
    of opRemove: edge.remove
  if result != nil:
    return result
  
  var newSig = src.signature
  case op
    of opAdd: newSig.insert(cid, newSig.lowerBound(cid))
    of opRemove: newSig.delete(newSig.binarySearch(cid))
  result = world.getOrCreateArchetype(newSig)

  case op
    of opAdd:
      src.edges[cid] = ArchetypeEdge(add: result, remove: edge.remove)
      result.edges.mgetOrPut(cid, ArchetypeEdge()).remove = src
    of opRemove:
      src.edges[cid] = ArchetypeEdge(add: edge.add, remove: result)
      result.edges.mgetOrPut(cid, ArchetypeEdge()).add = src

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

  # TODO: cache empty archetype
  let emptyArchetype = world.getOrCreateArchetype(@[])
  let row = emptyArchetype.entities.len
  emptyArchetype.entities.add(id)

  world.entities.records[id] = EntityRecord(archetype: emptyArchetype, row: row)
  result = Entity(world: world, id: id)

proc component*[T](world: var World, cType: typedesc[T]): EntityId =
  ## Registers a new component type T in the ECS world and returns its unique entity ID.
  let tid = typeId[T]()
  world.components.types.withValue(tid, val):
    return val[] # component type already registered, return existing ID
  var entity = world.spawn()
  world.components.types[tid] = entity.id
  entity[Component] = Component(info: newTypeInfo[T]())
  result = entity.id

proc id*(entity: Entity): EntityId =
  ## Returns the unique identifier of the entity.
  result = entity.id

proc isAlive*(entity: Entity): bool =
  ## Checks if the entity is alive in the ECS world.
  let world = entity.world
  result = entity.id in world.entities.records

proc has*(entity: Entity, id: EntityId): bool =
  ## Checks if this entity is associated with the entity of the given ID.
  let world = entity.world
  world.entities.records.withValue(entity.id, record):
    return world.tryGetColumn(record[], id) != -1
  do:
    return false # This entity does not exist in the world

proc has*[T](entity: Entity, cType: typedesc[T]): bool =
  ## Checks if the entity has a component of type T.
  let world = entity.world
  world.components.types.withValue(typeId[T](), val):
    let cid = val[]
    return entity.has(cid)
  do:
    return false # Component type T is not registered

template get0[T](entity: typed, cType: typedesc[T]) =
  var world = entity.world
  let entityRecord = world.entities.records[entity.id]
  let cid = world.getComponentId(T)
  let column = world.tryGetColumn(entityRecord, cid)
  if column == -1:
    raise newException(ValueError, "Entity does not have component of type " & $T)
  result = entityRecord.archetype.columns[column][entityRecord.row, T]

proc `[]`*[T](entity: Entity, cType: typedesc[T]): lent T =
  ## Retrieves the component of type T associated with the entity, if it exists.
  get0(entity, cType)

proc `[]`*[T](entity: var Entity, cType: typedesc[T]): var T =
  ## Retrieves the component of type T associated with the entity, if it exists.
  get0(entity, cType)

proc `[]=`*[T](entity: var Entity, cType: typedesc[T], value: sink T) =
  ## Associates a component of type T with the entity.
  var world = entity.world
  var entityRecord = world.entities.records[entity.id]
  let cid = world.component(T)

  world.entities.records.withValue(cid, componentRecord):
    componentRecord.archetypes.withValue(entityRecord.archetype.id, val):
      # component already present, overwrite it
      entityRecord.archetype.columns[val.column][entityRecord.row, T] = value
      return

    # need to move entity to a new archetype
    let dest = world.getOrCreateEdge(entityRecord.archetype, cid, opAdd)
    world.moveEntity(entity.id, dest)
    let newColumn = componentRecord.archetypes[dest.id].column
    dest.columns[newColumn].add(value)

proc remove*[T](entity: var Entity, cType: typedesc[T]) =
  ## Removes the component of type T from the entity, if it exists.
  var world = entity.world
  let entityRecord = world.entities.records[entity.id]
  let tid = typeId[T]()
  world.components.types.withValue(tid, val):
    let cid = val[]
    let componentRecord = world.entities.records[cid]
    if not componentRecord.archetypes.hasKey(entityRecord.archetype.id):
      return # entity doesn't have the component
    let dest = world.getOrCreateEdge(entityRecord.archetype, cid, opRemove)
    world.moveEntity(entity.id, dest)
  do:
    return # component type T is not registered, nothing to remove

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
  let tid = typeId[Component]()
  var entity = world.spawn()
  world.components.types[tid] = entity.id

  let sig = @[entity.id]
  let newId = world.archetypes.nextArchetypeId()
  world.entities.records[entity.id].archetypes[newId] = ArchetypeRecord(column: 0)
  let archetype = Archetype(
    id: newId,
    signature: sig,
    columns: @[initBlobSeq(newTypeInfo[Component]())],
    edges: initTable[EntityId, ArchetypeEdge]()
  )
  world.archetypes.table[sig] = archetype

  world.moveEntity(entity.id, archetype)
  archetype.columns[0].add(Component(info: newTypeInfo[Component]()))

proc newWorld*(): World =
  result = World()
  result.bootstrap()
