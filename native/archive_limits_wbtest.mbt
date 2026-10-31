///|
/// A deterministic reader with a finite payload or an endless stream. The
/// counters measure bytes really returned, including the EOF sentinel probe.
struct ArchiveBudgetTestReader {
  data : Bytes
  endless : Bool
  step : Int
  fail_at_call : Int
  buffer : @io.ReaderBuffer
  mut returned : Int
  mut calls : Int
  mut max_requested : Int
}

///|
fn ArchiveBudgetTestReader::new(
  data : Bytes,
  endless? : Bool = false,
  step? : Int = 4096,
  fail_at_call? : Int = -1,
) -> ArchiveBudgetTestReader {
  {
    data,
    endless,
    step,
    fail_at_call,
    buffer: @io.ReaderBuffer::new(),
    returned: 0,
    calls: 0,
    max_requested: 0,
  }
}

///|
impl @io.Reader for ArchiveBudgetTestReader with fn _get_internal_buffer(self) {
  self.buffer
}

///|
impl @io.Reader for ArchiveBudgetTestReader with fn _direct_read(
  self,
  destination,
  offset~,
  max_len~,
) {
  self.calls += 1
  if self.calls == self.fail_at_call {
    raise Failure("synthetic reader failure must not escape")
  }
  if max_len > self.max_requested {
    self.max_requested = max_len
  }
  let mut count = if max_len < self.step { max_len } else { self.step }
  if !self.endless && count > self.data.length() - self.returned {
    count = self.data.length() - self.returned
  }
  for index in 0..<count {
    destination[offset + index] = if self.endless {
      b'x'
    } else {
      self.data[self.returned + index]
    }
  }
  self.returned += count
  count
}

///|
#cfg(target="native")
async test "archive bounded reader accepts empty and exact limits" {
  let empty = ArchiveBudgetTestReader::new(b"")
  let data = read_archive_bytes(empty, 0L)
  inspect(data.length(), content="0")
  inspect(empty.returned, content="0")
  inspect(empty.calls, content="1")
  inspect(empty.max_requested, content="1")
  let exact = ArchiveBudgetTestReader::new(b"abcdef", step=2)
  let data = read_archive_bytes(exact, 6L)
  inspect(data == b"abcdef", content="true")
  inspect(exact.returned, content="6")
  inspect(exact.calls, content="4")
  inspect(exact.max_requested <= 7, content="true")
}

///|
#cfg(target="native")
async test "archive bounded reader consumes only limit plus one" {
  let reader = ArchiveBudgetTestReader::new(b"abcdefg-must-not-be-read")
  let rejected = try {
    let _ = read_archive_bytes(reader, 6L)
    false
  } catch {
    TooLarge(7L) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
  inspect(reader.returned, content="7")
  inspect(reader.calls, content="1")
}

///|
#cfg(target="native")
async test "archive bounded reader rejects infinite and one byte short reads" {
  for limit in [0L, 1L, 4095L, 4096L, 4100L] {
    for step in [1, 4096] {
      let reader = ArchiveBudgetTestReader::new(b"", endless=true, step~)
      let rejected = try {
        let _ = read_archive_bytes(reader, limit)
        false
      } catch {
        TooLarge(observed) => observed == limit + 1L
        _ => false
      } noraise {
        _ => false
      }
      inspect(rejected, content="true")
      inspect(reader.returned.to_int64() == limit + 1L, content="true")
      inspect(reader.max_requested <= 4096, content="true")
    }
  }
}

///|
#cfg(target="native")
async test "archive bounded reader preserves safe ReadFailed classification" {
  let reader = ArchiveBudgetTestReader::new(b"abcdef", step=1, fail_at_call=3)
  let rejected = try {
    let _ = read_archive_bytes(reader, 6L)
    false
  } catch {
    ReadFailed => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
  inspect(reader.returned, content="2")
  inspect(reader.calls, content="3")
}

///|
#cfg(target="native")
async test "archive bounded reader joins full blocks and final short read" {
  let expected = FixedArray::make(12_345, b'a').unsafe_reinterpret_as_bytes()
  let reader = ArchiveBudgetTestReader::new(expected, step=3)
  let actual = read_archive_bytes(reader, 12_345L)
  inspect(actual == expected, content="true")
  inspect(reader.returned, content="12345")
  inspect(reader.max_requested <= 4096, content="true")
}

///|
#cfg(target="native")
async test "archive bounded reader validates negative and huge Int64 budgets" {
  let negative = ArchiveBudgetTestReader::new(b"must-not-be-read")
  let rejected = try {
    let _ = read_archive_bytes(negative, -1L)
    false
  } catch {
    InvalidSizeLimit => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
  inspect(negative.calls, content="0")
  let huge = ArchiveBudgetTestReader::new(b"ok", step=1)
  let data = read_archive_bytes(huge, 9223372036854775807L)
  inspect(data == b"ok", content="true")
  inspect(huge.max_requested <= 4096, content="true")
}

///|
async fn archive_limits_remove(path : String) -> Unit {
  @fs.remove(path) catch {
    _ => ()
  }
}

///|
#cfg(target="native")
async test "archive loader enforces limit before UTF8 and JSON decoding" {
  let path = "_build/moonvcr-archive-budget-invalid-utf8.json"
  archive_limits_remove(path)
  defer archive_limits_remove(path)
  @fs.write_file(path, b"\xff\xfe\x00", create_mode=@fs.CreateNew)
  let rejected = try {
    let _ = load_cassette(path, 1L)
    false
  } catch {
    TooLarge(2L) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
#cfg(target="native")
async test "archive loader accepts an exact sized real cassette" {
  let path = "_build/moonvcr-archive-budget-exact.json"
  archive_limits_remove(path)
  defer archive_limits_remove(path)
  let original = @moonvcr.example_cassette()
  let encoded = @utf8.encode(original.encode())
  @fs.write_file(path, encoded, create_mode=@fs.CreateNew)
  let loaded = load_cassette(path, encoded.length().to_int64())
  inspect(loaded.encode() == original.encode(), content="true")
}

///|
#cfg(target="native")
async test "archive open handle is stable after deterministic path replacement" {
  let path = "_build/moonvcr-archive-budget-original.json"
  let replacement = "_build/moonvcr-archive-budget-replacement.json"
  archive_limits_remove(path)
  archive_limits_remove(replacement)
  defer archive_limits_remove(path)
  defer archive_limits_remove(replacement)
  @fs.write_file(path, b"original", create_mode=@fs.CreateNew)
  let file = @fs.open(path, mode=@fs.ReadOnly)
  defer file.close()
  @fs.write_file(
    replacement,
    b"replacement-exceeds-the-original-budget",
    create_mode=@fs.CreateNew,
  )
  @fs.rename(replacement, path, replace=true)
  let read_from_handle = read_archive_bytes(file, 8L)
  inspect(read_from_handle == b"original", content="true")
  let replaced_path_rejected = try {
    let _ = load_cassette(path, 8L)
    false
  } catch {
    TooLarge(9L) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(replaced_path_rejected, content="true")
}

///|
#cfg(target="native")
async test "archive open handle reads only budget plus one after file growth" {
  let path = "_build/moonvcr-archive-budget-growing.json"
  archive_limits_remove(path)
  defer archive_limits_remove(path)
  @fs.write_file(path, b"abcd", create_mode=@fs.CreateNew)
  let file = @fs.open(path, mode=@fs.ReadOnly)
  defer file.close()
  @fs.write_file(
    path,
    b"e-untouched-suffix",
    append=true,
    create_mode=@fs.OpenExisting,
  )
  let rejected = try {
    let _ = read_archive_bytes(file, 4L)
    false
  } catch {
    TooLarge(5L) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
  // The next byte is exactly byte six, proving that no read_all occurred.
  let unread = @io.Reader::read_exactly(file, 1)
  inspect(unread == b"-", content="true")
}
