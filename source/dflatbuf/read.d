module dflatbuf.read;

import std.file;
import std.stdio;

// FlatBuffer Primitives
alias uoffset_t = uint;
alias soffset_t = int;
alias voffset_t = ushort;

/**
 * Root wrapper around the binary buffer.
 * Contains no state other than the buffer slice.
 */
struct FlatBuffer {
  void[] buf;

  // Entry point: Get the root table.
  // The buffer starts with a uoffset_t to the root table.
  Table getRoot() const @nogc nothrow {
    if (buf.length < uoffset_t.sizeof)
      return Table(buf, 0);
    uoffset_t offset = read!uoffset_t(0);
    return Table(buf, offset);
  }

  // Helper to read scalars directly from buffer
  private T read(T)(size_t offset) const @nogc nothrow {
    // In a real app, add bounds checking here.
    // Assuming Little-Endian host (x86/ARM) as per FlatBuffer spec.
    return *cast(const(T)*)(buf.ptr + offset);
  }
}

/**
 * A view into a specific Table within the buffer.
 * created via offsets, does not copy data.
 */
struct Table {
  const void[] buf;
  size_t pos; // Absolute index in buf where this table starts

  // Core logic: Retrieve a scalar field from the VTable
  auto ref inout(T) getField(T)(size_t fieldIndex, T defaultVal) inout {
    if (auto p = getFieldPtr!T(fieldIndex)) {
      return *p;
    }
    return defaultVal;
  }

  // Core logic: Retrieve a scalar field from the VTable
  inout(T)* getFieldPtr(T)(size_t fieldIndex) inout {
    // Read the signed offset to the vtable (at the start of the table)
    soffset_t vtableOffset = read!soffset_t(pos);
    size_t vtablePos = pos - vtableOffset;
    voffset_t vtableSize = read!voffset_t(vtablePos);

    // Calculate where our field's offset is stored in the vtable.
    // The first two voffsets are [vtable_size, object_size], so fields start at +4 bytes.
    size_t vtableEntryOffset = vtablePos + 4 + (fieldIndex * 2);

    // Check if field is present in this vtable (versioning check)
    if (vtableEntryOffset >= vtablePos + vtableSize) {
      return null;
    }

    // Read the field offset (uint16)
    voffset_t fieldOffset = read!voffset_t(vtableEntryOffset);
    // If offset is 0, field is not present -> return default
    if (fieldOffset == 0) {
      return null;
    }
    return readPtr!T(pos + fieldOffset);
  }

  // Accessor for Strings (which are uoffset_t offset -> length prefixed byte array)
  const(char)[] getString(size_t fieldIndex) const @nogc nothrow {
    uoffset_t offsetToString = getField!uoffset_t(fieldIndex, 0);

    if (offsetToString == 0)
      return "";

    // String position is relative to the field's position
    // We need to manually recalculate the field position to add the relative offset.
    // (Re-doing vtable lookup manually for the relative base)
    soffset_t vtableOffset = read!soffset_t(pos);
    size_t vtablePos = pos - vtableOffset;
    size_t vtableEntryOffset = vtablePos + 4 + (fieldIndex * 2);
    voffset_t fieldOffset = read!voffset_t(vtableEntryOffset);

    size_t stringStartPos = pos + fieldOffset + offsetToString;
    uoffset_t len = read!uoffset_t(stringStartPos);
    size_t dataStart = stringStartPos + uoffset_t.sizeof;
    return cast(const(char)[]) buf[dataStart .. dataStart + len];
  }

  private inout(T) read(T)(size_t offset) inout {
    return *readPtr!T(offset);
  }

  private inout(T*) readPtr(T)(size_t offset) inout {
    return cast(inout(T)*)(buf.ptr + offset);
  }
}

unittest {
  // Manually constructing the binary buffer from the prompt's "Encoding Example"
  // https://github.com/google/flatbuffers/blob/master/docs/source/internals.md#encoding-example
  // { pos: { x: 1, y: 2, z: 3 }, name: "fred", hp: 50 }
  //
  // Binary Layout simulation (Little Endian):
  static const ubyte[] data = [
    // 0: Offset to root table (20)
    20, 0, 0, 0,

    // 4: VTable
    16, 0, // Size of vtable (16 bytes)
    22, 0, // Size of object
    4, 0, // Field 0 (pos struct) offset: 4
    0, 0, // Field 1 (padding/deprecated?): not present
    20, 0, // Field 2 (name string) offset: 20
    16, 0, // Field 3 (hp) offset: 16
    0, 0, 0, 0, // Padding to align to 20

    // 20: Root Table Start
    16, 0, 0, 0, // soffset_t to vtable (-16 bytes from here -> index 4)

    // 24: Field 0: Vec3 Struct (inline, x=1.0, y=2.0, z=3.0)
    0, 0, 128, 63, // float 1.0
    0, 0, 0, 64, // float 2.0
    0, 0, 64, 64, // float 3.0

    // 36: Field 3: HP (int16 = 50)
    50, 0,

    // 38: Padding
    0, 0,

    // 40: Field 2: Offset to Name (relative to here: 40)
    // String starts at 40 + 8 = 48
    8, 0, 0, 0,

    // 44: Padding
    0, 0, 0, 0,

    // 48: String "fred"
    4, 0, 0, 0, // Length 4
    'f', 'r', 'e', 'd',
    0 // Bytes
  ];

  // Deserialize
  FlatBuffer fb = FlatBuffer(cast(void[]) data);
  Table monster = fb.getRoot();

  // Read Struct (Field Index 0)
  assert(*monster.getFieldPtr!(float[3])(0) == [1f, 2f, 3f]);

  // Read Name (Field Index 2)
  assert(monster.getString(2) == "fred");

  // Read HP (Field Index 3)
  assert(*monster.getFieldPtr!short(3) == 50);
}

unittest {
  void[] buf = std.file.read("test/monsterdata.bin");
  FlatBuffer fb = FlatBuffer(buf);
  Table monster = fb.getRoot();
  assert(*monster.getFieldPtr!(float[3])(0) == [1f, 2f, 3f]);
  assert(*monster.getFieldPtr!(short)(2) == 300); // hp
  assert(monster.getString(3) == "Orc"); // "name"
  // TODO: support nested tables.
  // assert(monster.getString(3) == "Orc"); // "name"
}
