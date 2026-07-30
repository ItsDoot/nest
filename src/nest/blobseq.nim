type
  TypeInfo* = object
    ## Runtime type information.
    size*: int
    align*: int
    defaultConstruct*: proc (data: pointer) {.raises: [].}
      ## Initializes the memory at `data` to a default value of the type.
    copyConstruct*: proc (dest, src: pointer) {.raises: [].}
      ## Constructs a copy of the value at `src` into `dest`.
    moveConstruct*: proc (dest, src: pointer) {.raises: [].}
      ## Constructs a value at `dest` by moving the value from `src`.
    copyAssign*: proc (dest, src: pointer) {.raises: [].}
      ## Copies the value from `src` to `dest`.
    moveAssign*: proc (dest, src: pointer) {.raises: [].}
      ## Moves the value from `src` to `dest`.
    destroy*: proc (data: pointer) {.raises: [].}
      ## Destroys the value at `data`.
  BlobSeq* = object
    ## Homogenous type-erased sequence of items stored in a contiguous memory buffer.
    info: TypeInfo
    data: pointer
    len: int
    cap: int

proc newTypeInfo*[T](): TypeInfo =
  ## Creates a new TypeInfo object for the specified type T.
  result.size = sizeof(T)
  result.align = alignof(T)
  result.defaultConstruct = proc (data: pointer) =
    var temp = default(T)
    copyMem(data, unsafeAddr temp, sizeof(T))
    wasMoved(temp) # used to avoid deallocation of temp if it has a destructor
  result.copyConstruct = proc (dest, src: pointer) =
    var temp = `=dup`(cast[ptr T](src)[])
    copyMem(dest, unsafeAddr temp, sizeof(T))
    wasMoved(temp) # used to avoid deallocation of temp if it has a destructor
  result.moveConstruct = proc (dest, src: pointer) =
    var temp = move(cast[ptr T](src)[])
    copyMem(dest, unsafeAddr temp, sizeof(T))
    wasMoved(temp) # used to avoid deallocation of temp if it has a destructor
  result.copyAssign = proc (dest, src: pointer) =
    cast[ptr T](dest)[] = cast[ptr T](src)[] # Implicitly calls the `=copy` hook
  result.moveAssign = proc (dest, src: pointer) =
    cast[ptr T](dest)[] = move(cast[ptr T](src)[])
  result.destroy = proc (data: pointer) =
    `=destroy`(cast[ptr T](data)[])

proc initBlobSeq*(info: TypeInfo, capacity: int = 0): BlobSeq =
  ## Creates a new BlobSeq object with the specified TypeInfo and capacity.
  assert capacity >= 0, "Capacity must be non-negative"
  assert info.size mod info.align == 0, "Type size must be a multiple of its alignment"
  result.info = info
  result.len = 0
  result.cap = capacity
  if capacity > 0:
    result.data = allocShared(info.size * capacity)
  else:
    result.data = nil

proc initBlobSeq*[T](capacity: int = 0): BlobSeq =
  ## Creates a new BlobSeq object for the specified type T.
  result = initBlobSeq(newTypeInfo[T](), capacity)

proc len*(bs: BlobSeq): int =
  ## Returns the number of items currently stored in the BlobSeq.
  result = bs.len

proc grow*(bs: var BlobSeq, newCap: int = max(1, bs.cap * 2)) =
  ## Grows the BlobSeq to the specified new capacity.
  assert newCap > bs.cap, "New capacity must be greater than current capacity"
  bs.data = reallocShared(bs.data, bs.info.size * newCap)
  bs.cap = newCap

iterator items*(bs: var BlobSeq): pointer =
  ## Iterates over the items in the BlobSeq, yielding pointers to each item.
  for i in 0 ..< bs.len:
    yield cast[pointer](cast[int](bs.data) + i * bs.info.size)

template itemPtr(bs: BlobSeq, index: int): pointer =
  ## Computes the address of the item at `index` within the BlobSeq's buffer.
  assert index >= 0 and index < bs.len, "Index out of bounds"
  cast[pointer](cast[int](bs.data) + index * bs.info.size)

template appendItemPtr(bs: var BlobSeq): pointer =
  ## Computes the address of the next available slot for appending a new item.
  if bs.len == bs.cap:
    bs.grow()
  cast[pointer](cast[int](bs.data) + bs.len * bs.info.size)

template assertTypeInfo(bs: BlobSeq, T: typedesc): untyped =
  ## Asserts that the BlobSeq's TypeInfo matches the specified type T.
  assert bs.info.size == sizeof(T), "Type size mismatch"
  assert bs.info.align == alignof(T), "Type alignment mismatch"

proc swapRemove*(bs: var BlobSeq, index: int) =
  ## Destroys item at index and swap-removes it from the BlobSeq.
  let dest = itemPtr(bs, index)
  bs.info.destroy(dest)
  let lastIndex = bs.len - 1
  if index != lastIndex:
    let lastItemPtr = itemPtr(bs, lastIndex)
    bs.info.moveConstruct(dest, lastItemPtr)
  dec(bs.len)

proc transferItem*(dest: var BlobSeq, src: var BlobSeq, srcIndex: int) =
  ## Moves item at srcIndex from src into the end of dest, then swap-removes
  ## the (now empty) slot in src.
  assert dest.info.size == src.info.size, "Type size mismatch"
  assert dest.info.align == src.info.align, "Type alignment mismatch"
  let srcPtr = itemPtr(src, srcIndex)
  let destPtr = appendItemPtr(dest)
  dest.info.moveConstruct(destPtr, srcPtr)
  inc(dest.len)
  let lastIndex = src.len - 1
  if srcIndex != lastIndex:
    let lastSrcPtr = itemPtr(src, lastIndex)
    src.info.moveConstruct(srcPtr, lastSrcPtr)
  dec(src.len)

proc `[]`*(bs: BlobSeq, index: int): pointer =
  ## Returns a pointer to the item at the specified index in the BlobSeq.
  result = itemPtr(bs, index)

proc `[]`*[T](bs: BlobSeq, index: int, itemType: typedesc[T]): lent T =
  ## Returns a reference to the item of type T at the specified index in the BlobSeq.
  assertTypeInfo(bs, T)
  result = cast[ptr T](itemPtr(bs, index))[]

proc `[]`*[T](bs: var BlobSeq, index: int, itemType: typedesc[T]): var T =
  ## Returns a mutable reference to the item of type T at the specified index in the BlobSeq.
  assertTypeInfo(bs, T)
  result = cast[ptr T](itemPtr(bs, index))[]

proc `[]=`*[T](bs: BlobSeq, index: int, itemType: typedesc[T], value: sink T) =
  ## Sets the item of type T at the specified index in the BlobSeq.
  assertTypeInfo(bs, T)
  let dest = itemPtr(bs, index)
  bs.info.moveAssign(dest, unsafeAddr value)

proc add*[T](bs: var BlobSeq, value: sink T) =
  ## Adds a new item of type T to the end of the BlobSeq.
  assertTypeInfo(bs, T)
  let dest = appendItemPtr(bs)
  bs.info.moveConstruct(dest, unsafeAddr value)
  inc(bs.len)

proc addDefault*(bs: var BlobSeq) =
  ## Adds a new item of type T to the end of the BlobSeq, initialized to its default value.
  let dest = appendItemPtr(bs)
  bs.info.defaultConstruct(dest)
  inc(bs.len)

proc `=destroy`(bs: var BlobSeq) =
  if bs.data != nil:
    for p in bs:
      bs.info.destroy(p)
    deallocShared(bs.data)
    bs.data = nil

proc `=copy`(dest: var BlobSeq, src: BlobSeq) {.error.} =
  ## Copying is disabled.
  discard