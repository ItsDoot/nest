type
  TypeInfo* = object
    ## Runtime type information.
    size*: int
    align*: int
    copy*: proc (dest, src: pointer) {.raises: [].}
    move*: proc (dest, src: pointer) {.raises: [].}
    destroy*: proc (data: pointer) {.raises: [].}
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
  result.copy = proc (dest, src: pointer) =
    # Implicitly calls the `=copy` hook
    cast[ptr T](dest)[] = cast[ptr T](src)[]
  result.move = proc (dest, src: pointer) =
    cast[ptr T](dest)[] = move(cast[ptr T](src)[])
  result.destroy = proc (data: pointer) =
    `=destroy`(cast[ptr T](data)[])

proc initBlobSeq*(info: TypeInfo, capacity: int = 0): BlobSeq =
  ## Creates a new BlobSeq object with the specified TypeInfo and capacity.
  assert capacity >= 0, "Capacity must be non-negative"
  result.info = info
  result.len = 0
  result.cap = capacity
  if capacity > 0:
    result.data = allocShared0(info.size * capacity)
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
  # TODO: maybe just reallocShared (non-zeroing)?
  bs.data = reallocShared0(bs.data, bs.info.size * bs.cap, bs.info.size * newCap)
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

proc swapRemove*(bs: var BlobSeq, index: int) =
  ## Destroys item at index and swap-removes it from the BlobSeq.
  let p = itemPtr(bs, index)
  bs.info.destroy(p)
  let lastIndex = bs.len - 1
  if index != lastIndex:
    let lastItemPtr = itemPtr(bs, lastIndex)
    bs.info.move(p, lastItemPtr)
  dec(bs.len)

proc transferItem*(dest: var BlobSeq, src: var BlobSeq, srcIndex: int) =
  ## Moves item at srcIndex from src into the end of dest, then swap-removes
  ## the (now empty) slot in src.
  assert dest.info.size == src.info.size, "Type size mismatch"
  assert dest.info.align == src.info.align, "Type alignment mismatch"
  let srcPtr = itemPtr(src, srcIndex)
  let destPtr = appendItemPtr(dest)
  dest.info.move(destPtr, srcPtr)
  inc(dest.len)
  let lastIndex = src.len - 1
  if srcIndex != lastIndex:
    let lastSrcPtr = itemPtr(src, lastIndex)
    src.info.move(srcPtr, lastSrcPtr)
  dec(src.len)

proc `[]`*[T](bs: BlobSeq, index: int, itemType: typedesc[T]): lent T =
  ## Returns a reference to the item of type T at the specified index in the BlobSeq.
  assert sizeof(T) == bs.info.size, "Type size mismatch"
  assert alignof(T) == bs.info.align, "Type alignment mismatch"
  result = cast[ptr T](itemPtr(bs, index))[]

proc `[]`*[T](bs: var BlobSeq, index: int, itemType: typedesc[T]): var T =
  ## Returns a mutable reference to the item of type T at the specified index in the BlobSeq.
  assert sizeof(T) == bs.info.size, "Type size mismatch"
  assert alignof(T) == bs.info.align, "Type alignment mismatch"
  result = cast[ptr T](itemPtr(bs, index))[]

proc `[]=`*[T](bs: BlobSeq, index: int, itemType: typedesc[T], value: sink T) =
  ## Sets the item of type T at the specified index in the BlobSeq.
  assert sizeof(T) == bs.info.size, "Type size mismatch"
  assert alignof(T) == bs.info.align, "Type alignment mismatch"
  let p = itemPtr(bs, index)
  bs.info.destroy(p)
  bs.info.move(p, unsafeAddr value)

proc add*[T](bs: var BlobSeq, value: sink T) =
  ## Adds a new item of type T to the end of the BlobSeq.
  let p = appendItemPtr(bs)
  bs.info.move(p, unsafeAddr value)
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