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
/// Load and decode a cassette only after checking its byte size.
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
  let size = @fs.file_size(path) catch { _ => raise ReadFailed }
  if size > max_bytes {
    raise TooLarge(size)
  }
  let data = @fs.read_file(path) catch { _ => raise ReadFailed }
  let text = data.text() catch { _ => raise ReadFailed }
  let cassette = @moonvcr.Cassette::decode(text) catch {
    error => raise DecodeFailed(error)
  }
  if cassette.interactions.length() > max_interactions {
    raise TooManyInteractions(cassette.interactions.length())
  }
  cassette
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
