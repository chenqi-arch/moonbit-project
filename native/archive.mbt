///|
/// Errors returned by the native cassette file adapter.
pub suberror ArchiveError {
  MissingFile
  TooLarge(Int64)
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
async fn exists(path : String) -> Bool raise ArchiveError {
  @fs.exists(path) catch {
    _ => raise ReadFailed
  }
}

///|
/// Load a cassette from a UTF-8 JSON file with an explicit byte limit.
pub async fn load_cassette(
  path : String,
  max_bytes : Int64,
) -> @moonvcr.Cassette raise ArchiveError {
  if !exists(path) {
    raise MissingFile
  }
  let size = @fs.file_size(path) catch { _ => raise ReadFailed }
  if size > max_bytes {
    raise TooLarge(size)
  }
  let data = @fs.read_file(path) catch { _ => raise ReadFailed }
  let text = data.text() catch { _ => raise ReadFailed }
  @moonvcr.Cassette::decode(text) catch {
    error => raise DecodeFailed(error)
  }
}

///|
/// Load a cassette using the conservative default size limit.
pub async fn load_cassette_default(
  path : String,
) -> @moonvcr.Cassette raise ArchiveError {
  load_cassette(path, DEFAULT_MAX_CASSETTE_BYTES)
}

///|
/// Save a cassette without overwriting an existing destination. The temporary
/// file is created next to the destination and renamed only after a synced
/// write succeeds.
pub async fn save_cassette_new(
  path : String,
  cassette : @moonvcr.Cassette,
) -> Unit raise ArchiveError {
  if exists(path) {
    raise AlreadyExists
  }
  let temporary = path + ".moonvcr.tmp"
  if exists(temporary) {
    raise TemporaryFileExists
  }
  let text = @moonvcr.Cassette::encode(cassette)
  @fs.write_file(temporary, text, create_mode=@fs.CreateNew, sync=@fs.Data) catch {
    _ => raise WriteFailed
  }
  @fs.rename(temporary, path, replace=false) catch {
    _ => {
      @fs.remove(temporary) catch {
        _ => ()
      }
      raise ReplaceFailed
    }
  }
}

///|
/// Replace a destination only when the caller explicitly requests it.
pub async fn save_cassette_replace(
  path : String,
  cassette : @moonvcr.Cassette,
) -> Unit raise ArchiveError {
  let temporary = path + ".moonvcr.tmp"
  if exists(temporary) {
    raise TemporaryFileExists
  }
  let text = @moonvcr.Cassette::encode(cassette)
  @fs.write_file(temporary, text, create_mode=@fs.CreateNew, sync=@fs.Data) catch {
    _ => raise WriteFailed
  }
  @fs.rename(temporary, path, replace=true) catch {
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
    TooLarge(size) => "cassette exceeds size limit: " + size.to_string()
    ReadFailed => "cassette file read failed"
    DecodeFailed(_) => "cassette JSON decode failed"
    AlreadyExists => "cassette destination already exists"
    TemporaryFileExists => "cassette temporary file already exists"
    WriteFailed => "cassette file write failed"
    ReplaceFailed => "cassette destination replace failed"
  }
}
