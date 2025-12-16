# dflatbuf

D language implementation of Flatbuffers.

This library requires no external deps nor flatc code generation. Instead dflatbuf uses D's compile-time function execution (CTFE) and `mixin(path-to-schema)` for loading schema files and generating D modules.

## References

- https://flatbuffers.dev/internals/ for understanding serialized binary structures.
- https://flatbuffers.dev/tutorial/ for usages in other languages.
- https://flatbuffers.dev/grammar/ for EBNF fbs schema syntax.
- https://flatbuffers.dev/flatc/ for printing JSON and dumping bin files.
