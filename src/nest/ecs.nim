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
    edges: TableRef[EntityId, ArchetypeEdge]
      ## A mapping of component IDs to their corresponding archetype edges.
  
  ArchetypeEdge* = object
    ## The transition from one archetype to another when adding or removing a component.
    add: Archetype
    remove: Archetype

  Archetypes* = object
    nextId: ArchetypeId
      ## The next available archetype ID.
    table: TableRef[Signature, Archetype]
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
    archetypes: TableRef[ArchetypeId, ArchetypeRecord]
      ## A mapping of archetype IDs to their corresponding archetype records.
      ## Nil if the entity is not a component entity.

  Entities* = object
    nextId: EntityId
      ## The next available entity ID.
    records: TableRef[EntityId, EntityRecord]
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

proc getTypeInfo(world: World, cid: EntityId): TypeInfo =
  ## Retrieves the TypeInfo of a component given its entity ID.
  let entityRecord = world.entities.records[cid]
  let componentCId = world.components.types[typeId[Component]()]
  let componentRecord = world.entities.records[componentCId]
  let column = componentRecord.archetypes[entityRecord.archetype.id].column
  result = entityRecord.archetype.columns[column][entityRecord.row, Component].info

proc getOrCreateArchetype(world: var World, sig: sink Signature): Archetype =
  ## Retrieves an existing archetype with the specified signature or creates a new one if it doesn't exist.
  sig.sort()

  if sig in world.archetypes.table:
    return world.archetypes.table[sig]

  let newId = world.archetypes.nextArchetypeId()

  var columns = newSeq[Column](sig.len)
  for i, cid in sig:
    var record = world.entities.records[cid]
    columns[i] = initBlobSeq(world.getTypeInfo(cid))
    record.archetypes[newId] = ArchetypeRecord(column: i)

  result = Archetype(
    id: newId,
    signature: sig,
    columns: columns,
    edges: newTable[EntityId, ArchetypeEdge]()
  )
  world.archetypes.table[sig] = result

proc moveEntity(world: var World, id: EntityId, dst: Archetype) =
  ## Moves an entity to a new archetype, updating its record and transferring its components.
  let record = world.entities.records[id]
  let src = record.archetype
  let newRow = dst.entities.len
  dst.entities.add(id)

  for i, cid in src.signature:
    let dstCol = dst.signature.find(cid)
    if dstCol >= 0:
      dst.columns[dstCol].transferItem(src.columns[i], record.row)
    else:
      src.columns[i].swapRemove(record.row)
  
  let lastRow = src.entities.len - 1
  if record.row != lastRow:
    let lastEntityId = src.entities[lastRow]
    world.entities.records[lastEntityId].row = record.row
    src.entities[record.row] = lastEntityId
  src.entities.setLen(lastRow)

  world.entities.records[id] = EntityRecord(archetype: dst, row: newRow, archetypes: record.archetypes)
  

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
  let tid = typeId[T]()
  if tid notin world.components.types:
    raise newException(ValueError, "Component type " & $T & " is not registered")
  let cid = world.components.types[tid]
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

  let emptyArchetype = world.getOrCreateArchetype(@[])
  let row = emptyArchetype.entities.len
  emptyArchetype.entities.add(id)

  world.entities.records[id] = EntityRecord(archetype: emptyArchetype, row: row)
  result = Entity(world: world, id: id)

proc component*[T](world: var World, cType: typedesc[T]): EntityId =
  ## Registers a new component type T in the ECS world and returns its unique entity ID.
  let tid = typeId[T]()
  if tid in world.components.types:
    return world.components.types[tid] # component type already registered, return existing ID
  var entity = world.spawn()
  world.components.types[tid] = entity.id
  world.entities.records[entity.id].archetypes = newTable[ArchetypeId, ArchetypeRecord]()
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
  if entity.id notin world.entities.records:
    return false # This entity does not exist in the world
  if id notin world.entities.records:
    return false # The component entity does not exist in the world
  let entityRecord = world.entities.records[entity.id]
  let componentRecord = world.entities.records[id]
  if componentRecord.archetypes == nil:
    return false
  result = componentRecord.archetypes.hasKey(entityRecord.archetype.id)

proc has*[T](entity: Entity, cType: typedesc[T]): bool =
  ## Checks if the entity has a component of type T.
  let world = entity.world
  let tid = typeId[T]()
  if tid notin world.components.types:
    return false # Component type T is not registered
  let cid = world.components.types[tid]
  result = entity.has(cid)

proc `[]`*[T](entity: Entity, cType: typedesc[T]): lent T =
  ## Retrieves the component of type T associated with the entity, if it exists.
  let world = entity.world
  let entityRecord = world.entities.records[entity.id]
  let tid = typeId[T]()
  if tid notin world.components.types:
    raise newException(ValueError, "Component type " & $T & " is not registered")
  let cid = world.components.types[tid]
  let componentRecord = world.entities.records[cid]
  if not componentRecord.archetypes.hasKey(entityRecord.archetype.id):
    raise newException(ValueError, "Entity does not have component of type " & $T)
  let column = componentRecord.archetypes[entityRecord.archetype.id].column
  result = entityRecord.archetype.columns[column][entityRecord.row, T]

proc `[]`*[T](entity: var Entity, cType: typedesc[T]): var T =
  ## Retrieves the component of type T associated with the entity, if it exists.
  var world = entity.world
  let entityRecord = world.entities.records[entity.id]
  let tid = typeId[T]()
  if tid notin world.components.types:
    raise newException(ValueError, "Component type " & $T & " is not registered")
  let cid = world.components.types[tid]
  let componentRecord = world.entities.records[cid]
  if not componentRecord.archetypes.hasKey(entityRecord.archetype.id):
    raise newException(ValueError, "Entity does not have component of type " & $T)
  let column = componentRecord.archetypes[entityRecord.archetype.id].column
  result = entityRecord.archetype.columns[column][entityRecord.row, T]

proc `[]=`*[T](entity: var Entity, cType: typedesc[T], value: sink T) =
  ## Associates a component of type T with the entity.
  var world = entity.world
  var entityRecord = world.entities.records[entity.id]
  let cid = world.component(T)
  let componentRecord = world.entities.records[cid]

  if componentRecord.archetypes.hasKey(entityRecord.archetype.id):
    # component already present, overwrite it
    let column = componentRecord.archetypes[entityRecord.archetype.id].column
    entityRecord.archetype.columns[column][entityRecord.row, T] = value
    return

  # need to move entity to a new archetype
  var dest = entityRecord.archetype.edges.getOrDefault(cid).add
  if dest == nil:
    # create new archetype with the added component
    var newSig = entityRecord.archetype.signature
    newSig.add(cid)
    dest = world.getOrCreateArchetype(newSig)
    entityRecord.archetype.edges[cid] = ArchetypeEdge(add: dest, remove: entityRecord.archetype.edges.getOrDefault(cid).remove)
    dest.edges[cid] = ArchetypeEdge(add: dest.edges.getOrDefault(cid).add, remove: entityRecord.archetype)

  world.moveEntity(entity.id, dest)
  let newColumn = componentRecord.archetypes[dest.id].column
  dest.columns[newColumn].add(value)

proc remove*[T](entity: var Entity, cType: typedesc[T]) =
  ## Removes the component of type T from the entity, if it exists.
  var world = entity.world
  let entityRecord = world.entities.records[entity.id]
  let tid = typeId[T]()
  if tid notin world.components.types:
    return # component isn't registered
  let cid = world.components.types[tid]
  let componentRecord = world.entities.records[cid]
  if not componentRecord.archetypes.hasKey(entityRecord.archetype.id):
    return # entity doesn't have the component

  var dest = entityRecord.archetype.edges[cid].remove
  if dest == nil:
    # create/find new archetype without the removed component
    var newSig = entityRecord.archetype.signature
    newSig.delete(newSig.find(cid))
    dest = world.getOrCreateArchetype(newSig)
    entityRecord.archetype.edges[cid] = ArchetypeEdge(add: entityRecord.archetype.edges[cid].add, remove: dest)
    dest.edges[cid] = ArchetypeEdge(add: entityRecord.archetype, remove: dest.edges[cid].remove)
  world.moveEntity(entity.id, dest)

proc destroy*(entity: sink Entity) =
  ## Destroys the entity and removes it from the ECS world.
  if not entity.isAlive():
    return

  if entity.has(Component):
    raise newException(ValueError, "Cannot destroy component entities")

  let record = entity.world.entities.records[entity.id]

  for col in record.archetype.columns.mitems:
    col.swapRemove(record.row)
  
  let lastRow = record.archetype.entities.len - 1
  if record.row != lastRow:
    let lastEntityId = record.archetype.entities[lastRow]
    entity.world.entities.records[lastEntityId].row = record.row
    record.archetype.entities[record.row] = lastEntityId
  record.archetype.entities.setLen(lastRow)

  entity.world.entities.records.del(entity.id)

##################################################
# WORLD MANAGEMENT
##################################################

proc bootstrap(world: var World) =
  ## Bootstraps the ECS world by seeding the archetype that holds `Component` entities.
  let tid = typeId[Component]()
  var entity = world.spawn()
  world.components.types[tid] = entity.id
  world.entities.records[entity.id].archetypes = newTable[ArchetypeId, ArchetypeRecord]()

  let sig = @[entity.id]
  let newId = world.archetypes.nextArchetypeId()
  world.entities.records[entity.id].archetypes[newId] = ArchetypeRecord(column: 0)
  let archetype = Archetype(
    id: newId,
    signature: sig,
    columns: @[initBlobSeq(newTypeInfo[Component]())],
    edges: newTable[EntityId, ArchetypeEdge]()
  )
  world.archetypes.table[sig] = archetype

  world.moveEntity(entity.id, archetype)
  archetype.columns[0].add(Component(info: newTypeInfo[Component]()))

proc newWorld*(): World =
  result = World(
    archetypes: Archetypes(table: newTable[Signature, Archetype]()),
    entities: Entities(nextId: EntityId(0), records: newTable[EntityId, EntityRecord]()),
    components: Components(types: initTable[TypeId, EntityId]())
  )
  result.bootstrap()
