module dflatbuf.write;

import core.stdc.string : memcpy;
import core.stdc.stdio : printf;

// FlatBuffer Primitives
alias uoffset_t = uint;
alias soffset_t = int;
alias voffset_t = ushort;

/**
 * A Fixed Buffer implementation that replaces heap allocation.
 * Contains the raw memory for the FlatBuffer.
 */
struct FixedBuffer {
  // Arbitrarily large static storage for the buffer content.
  enum MAX_SIZE = 1024;
  private ubyte[MAX_SIZE] data;
  private size_t head = MAX_SIZE; // The lowest used address (grows downwards)

  // Aligns the head to 'alignSize' by inserting padding (zeros)
  void alignTo(size_t alignSize) @nogc nothrow {
    size_t mask = alignSize - 1;
    size_t padding = (head & mask);
    if (padding > 0) {
      padding = alignSize - padding;
      head -= padding;
      // Zero out padding bytes (optional, but good practice)
      // Note: memset is not strictly @nogc but direct loop is safe.
      for (size_t i = 0; i < padding; ++i) {
        data[head + i] = 0;
      }
    }
  }

  // Writes a scalar value T at the current head after aligning.
  size_t push(T)(T value) @nogc nothrow {
    alignTo(T.sizeof);
    head -= T.sizeof;

    // Write the value to the buffer (assuming Little Endian host)
    *cast(T*)(data.ptr + head) = value;
    return head; // Return the absolute position of the written item
  }

  // Helper to write a block of raw bytes (used for strings/vectors)
  size_t pushBytes(const(void)* src, size_t size, size_t alignment) @nogc nothrow {
    alignTo(alignment);
    head -= size;
    memcpy(data.ptr + head, src, size);
    return head;
  }

  // Returns the finished buffer content (from the head up to the end)
  const(ubyte)[] getBuffer() const @nogc nothrow {
    return data[head .. data.length];
  }
}


/**
 * Core Builder: Manages the construction process and VTable offsets.
 */
struct FlatBufferBuilder {
  FixedBuffer storage;
  size_t objectStart; // Absolute position where the current Table object starts
  voffset_t[32] fieldOffsets; // Store field offsets (index in array = field index)
  size_t maxAlign = 1; // Tracks max alignment needed for the current table

  // --- High-Level Operations ---

  // 1. Starts a new Table. Marks the current head position.
  size_t startTable() @nogc nothrow {
    maxAlign = 1; // Reset alignment for the new table
    objectStart = storage.head;
    fieldOffsets[] = 0; // Clear all field offsets
    return objectStart;
  }

  // 2. Adds a scalar field to the current Table.
  void addField(T)(size_t fieldIndex, T value, T defaultValue) @nogc nothrow {
    // Skip default values (a key FlatBuffers optimization)
    if (value == defaultValue) {
      return;
    }

    // Add the field backwards and record its relative offset.
    size_t absPos = storage.push(value);
    voffset_t relativeOffset = cast(voffset_t)(objectStart - absPos);
    fieldOffsets[fieldIndex] = relativeOffset;

    // Update the maximum alignment needed for the object.
    if (T.sizeof > maxAlign) {
      maxAlign = T.sizeof;
    }
  }

  // 3. Adds an offset field (to a String/Vector/Child Table)
  void addOffset(size_t fieldIndex, size_t absolutePos) @nogc nothrow {
    if (absolutePos == 0) return; // Null offset

    // Calculate offset (uoffset_t) from the field's future location (objectStart)
    // to the target object's location (absolutePos).
    // Since we write objects backwards, objectStart is a lower address than absolutePos.
    uoffset_t offset = cast(uoffset_t)(absolutePos - storage.head);

    // Add the offset field backwards
    size_t absPos = storage.push(offset);
    voffset_t relativeOffset = cast(voffset_t)(objectStart - absPos);
    fieldOffsets[fieldIndex] = relativeOffset;

    // uoffset_t is 4 bytes, so max align is 4
    if (uoffset_t.sizeof > maxAlign) {
      maxAlign = uoffset_t.sizeof;
    }
  }

  // 4. Ends the Table, writes the VTable, and writes the VTable offset.
  size_t endTable(size_t numFields) @nogc nothrow {
    // 4a. Align the entire object to its max alignment (maxAlign)
    storage.alignTo(maxAlign);

    // Calculate the object size (for the VTable)
    size_t tableSize = objectStart - storage.head;

    // 4b. Write the VTable contents backwards
    // (For a minimal writer, we skip VTable sharing and write it fresh)
    size_t vtableStart = storage.head;
    voffset_t vtableLength = cast(voffset_t)(4 + numFields * 2); // 2 header + numFields * 2 bytes

    // Write field offsets backwards
    for (size_t i = numFields; i > 0; --i) {
      storage.push(fieldOffsets[i - 1]);
    }

    // Write header (object size, then vtable length)
    storage.push(cast(voffset_t)tableSize);
    storage.push(vtableLength);

    // 4c. Write the soffset_t to the VTable at the new table start
    // This is a NEGATIVE offset: TableStart - VTableStart
    size_t currentTableStart = storage.head;
    soffset_t vtableOffset = cast(soffset_t)(currentTableStart - vtableStart);
    storage.push(-vtableOffset); // Negative offset is stored

    return currentTableStart; // Return absolute position of the new Table
  }

  // 5. Finalize the entire buffer by writing the root offset.
  void finish(size_t absoluteRootPos) @nogc nothrow {
    // Final alignment to 4 bytes for the uoffset_t root pointer
    storage.alignTo(uoffset_t.sizeof);

    // Root offset: points from the buffer's start (head) to the root object.
    uoffset_t rootOffset = cast(uoffset_t)(storage.head - absoluteRootPos);
    storage.push(rootOffset);
  }

  // --- Helpers for Complex Types ---

  // Writes a null-terminated string/key (no length prefix)
  size_t createString(const(char)[] str) @nogc nothrow {
    // Align to 1 byte (for the string data)
    storage.alignTo(1);

    // 1. Write null terminator
    storage.push(cast(ubyte)0);

    // 2. Write string bytes
    size_t stringStart = storage.pushBytes(str.ptr, str.length, 1);

    // 3. Write length prefix (uoffset_t)
    uoffset_t len = cast(uoffset_t)str.length;
    storage.push(len);

    return storage.head; // Absolute position of the length prefix
  }
}


// --- Example Usage matching the Monster Schema ---
unittest {
  FlatBufferBuilder fbb;

  // 1. Write the String object (children first)
  // String is "fred"
  const(char)[] nameStr = "fred";
  size_t namePos = fbb.createString(nameStr);

  // 2. Write the Root Table (Monster)
  // Field Map (Arbitrary, based on schema): 0:pos, 2:name, 3:hp
  size_t monsterStart = fbb.startTable();

  // 2a. Add HP (Field Index 3) - int16
  // Default value is 100, we set 50.
  fbb.addField!short(3, 50, 100);

  // 2b. Add Name (Field Index 2) - uoffset_t to String
  fbb.addOffset(2, namePos);

  // 2c. Add Pos (Field Index 0) - Vec3 struct (skipping for minimalism,
  // but in a full version, this is where you'd write the inline struct)
  // We will just add a dummy float to simulate the space.
  fbb.addField!float(0, 1.0f, 0.0f); // Simulating the start of the inline struct

  // 2d. End Table and get its absolute position
  size_t monsterPos = fbb.endTable(4); // 4 fields in the original schema (max index + 1)

  // 3. Finalize the buffer
  fbb.finish(monsterPos);

  // 4. Output the result
  const(ubyte)[] buffer = fbb.storage.getBuffer();

  printf("--- Minimal FlatBuffer Binary Output ---\n");
  printf("Buffer size: %d bytes. Head starts at: %d\n",
         cast(int)buffer.length, cast(int)fbb.storage.head);

  printf("Content (hex): ");
  // foreach (i; 0 .. buffer.length / 2) {
  //   printf("%d ", *(cast(ushort*) buffer.ptr + i * 2));
  // }
  foreach (b; buffer)  {
    printf("%02x ", b);
  }
  printf("\n");

  import std.file;
  const(ubyte)[] refbin = cast(const(ubyte)[]) std.file.read("test/monsterdata_simple.bin");
  foreach (b; refbin)  {
    printf("%02x ", b);
  }
  printf("\n");

}
