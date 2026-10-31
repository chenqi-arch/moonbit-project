///|
/// Errors returned by the native cassette file adapter.
pub suberror ArchiveError {
  MissingFile
  InvalidSizeLimit
  InvalidInteractionLimit
  TooLarge(Int64)
  TooManyInteractions(Int)
  ReadFailed
  DecodeFailed(@moonvcr.CassetteError)
  AlreadyExists
  TemporaryFileExists
  WriteFailed
  ReplaceFailed
} derive(@debug.Debug)

///|
pub const DEFAULT_MAX_CASSETTE_BYTES : Int64 = 10_000_000L

///|
pub const DEFAULT_MAX_CASSETTE_INTERACTIONS : Int = 100_000

///|
async fn archive_exists(path : String) -> Bool raise ArchiveError {
  @fs.exists(path) catch {
    _ => raise ReadFailed
  }
}

///|
/// Load and decode a cassette only after reading it within a hard byte budget.
pub async fn load_cassette(
  path : String,
  max_bytes : Int64,
) -> @moonvcr.Cassette raise ArchiveError {
  load_cassette_with_limits(path, max_bytes, DEFAULT_MAX_CASSETTE_INTERACTIONS)
}

///|
/// Load with explicit byte and decoded-interaction limits.
pub async fn load_cassette_with_limits(
  path : String,
  max_bytes : Int64,
  max_interactions : Int,
) -> @moonvcr.Cassette raise ArchiveError {
  if max_bytes < 0L {
    raise InvalidSizeLimit
  }
  if max_interactions < 0 {
    raise InvalidInteractionLimit
  }
  if !archive_exists(path) {
    raise MissingFile
  }
  let file = @fs.open(path, mode=@fs.ReadOnly) catch { _ => raise ReadFailed }
  defer file.close()
  let data = read_archive_bytes(file, max_bytes)
  let text = @utf8.decode(data) catch { _ => raise ReadFailed }
  let cassette = @moonvcr.Cassette::decode(text) catch {
    error => raise DecodeFailed(error)
  }
  if cassette.interactions.length() > max_interactions {
    raise TooManyInteractions(cassette.interactions.length())
  }
  cassette
}

///|
/// Read through one already-open reader, consuming at most max_bytes plus one
/// sentinel byte. File size metadata is not an input: a file which grows after
/// open must obey exactly the same budget as a finite or infinite stream.
///
/// Short reads fill the same block; the block list grows only once per 4096
/// actual bytes, not once per read. No allocation uses the configured limit as
/// a capacity. The final Bytes allocation uses only the observed accepted size.
async fn[R : @io.Reader] read_archive_bytes(
  reader : R,
  max_bytes : Int64,
) -> Bytes raise ArchiveError {
  if max_bytes < 0L {
    raise InvalidSizeLimit
  }
  let block_size = if max_bytes < 4096L { max_bytes.to_int() + 1 } else { 4096 }
  let blocks : Array[FixedArray[Byte]] = []
  let mut block = FixedArray::make(block_size, b'\x00')
  let mut used = 0
  let mut total = 0
  while true {
    let remaining = max_bytes - total.to_int64()
    let available = block.length() - used
    // Only form remaining + 1 after proving that it is smaller than one
    // block. In particular max_bytes = Int64::MAX never overflows here.
    let requested = if remaining >= available.to_int64() {
      available
    } else {
      remaining.to_int() + 1
    }
    let received = @io.Reader::read(
      reader,
      block,
      offset=used,
      max_len=requested,
    ) catch {
      _ => raise ReadFailed
    }
    if received < 0 || received > requested {
      raise ReadFailed
    }
    if received == 0 {
      break
    }
    if received.to_int64() > remaining {
      raise TooLarge(total.to_int64() + received.to_int64())
    }
    // Bytes/FixedArray are Int-indexed even when the caller supplies an Int64
    // budget. Reject an unrepresentable payload before an Int addition wraps.
    if total > 2147483647 - received {
      raise TooLarge(total.to_int64() + received.to_int64())
    }
    total += received
    used += received
    if used == block.length() {
      blocks.push(block)
      block = FixedArray::make(block_size, b'\x00')
      used = 0
    }
    continue
  }
  let result = FixedArray::make(total, b'\x00')
  let mut copied = 0
  for complete in blocks {
    result.unsafe_blit(copied, complete, 0, complete.length())
    copied += complete.length()
  }
  result.unsafe_blit(copied, block, 0, used)
  result.unsafe_reinterpret_as_bytes()
}

///|
pub async fn load_cassette_default(
  path : String,
) -> @moonvcr.Cassette raise ArchiveError {
  load_cassette(path, DEFAULT_MAX_CASSETTE_BYTES)
}

///|
/// Write to a new neighboring temporary file, sync it, and rename only after
/// the complete payload is durable. The destination is never overwritten.
pub async fn save_cassette_new(
  path : String,
  cassette : @moonvcr.Cassette,
) -> Unit raise ArchiveError {
  if archive_exists(path) {
    raise AlreadyExists
  }
  save_cassette(path, cassette, replace=false)
}

///|
/// Replace a destination only when the caller explicitly selects this API.
pub async fn save_cassette_replace(
  path : String,
  cassette : @moonvcr.Cassette,
) -> Unit raise ArchiveError {
  save_cassette(path, cassette, replace=true)
}

///|
async fn save_cassette(
  path : String,
  cassette : @moonvcr.Cassette,
  replace~ : Bool,
) -> Unit raise ArchiveError {
  let temporary = path + ".moonvcr.tmp"
  if archive_exists(temporary) {
    raise TemporaryFileExists
  }
  let text = @moonvcr.Cassette::encode(cassette)
  @fs.write_file(temporary, text, create_mode=@fs.CreateNew, sync=@fs.Data) catch {
    _ => raise WriteFailed
  }
  @fs.rename(temporary, path, replace~) catch {
    _ => {
      @fs.remove(temporary) catch {
        _ => ()
      }
      raise ReplaceFailed
    }
  }
}

///|
pub fn ArchiveError::summary(self : ArchiveError) -> String {
  match self {
    MissingFile => "cassette file missing"
    InvalidSizeLimit => "cassette size limit must not be negative"
    InvalidInteractionLimit => "cassette interaction limit must not be negative"
    TooLarge(size) => "cassette exceeds size limit: " + size.to_string()
    TooManyInteractions(count) =>
      "cassette exceeds interaction limit: " + count.to_string()
    ReadFailed => "cassette file read failed"
    DecodeFailed(_) => "cassette JSON decode failed"
    AlreadyExists => "cassette destination already exists"
    TemporaryFileExists => "cassette temporary file already exists"
    WriteFailed => "cassette file write failed"
    ReplaceFailed => "cassette destination replace failed"
  }
}
