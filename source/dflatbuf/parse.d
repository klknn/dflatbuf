module dflatbuf.parse;

// https://github.com/google/flatbuffers/blob/master/samples/monster.fbs
string monstersFbs = `
// Example IDL file for our monster's schema.

namespace MyGame.Sample;

enum Color:byte { Red = 0, Green, Blue = 2 }

union Equipment { Weapon } // Optionally add more tables.

struct Vec3 {
  x:float;
  y:float;
  z:float;
}

table Monster {
  pos:Vec3;
  mana:short = 150;
  hp:short = 100;
  name:string;
  friendly:bool = false (deprecated);
  inventory:[ubyte];
  color:Color = Blue;
  weapons:[Weapon];
  equipped:Equipment;
  path:[Vec3];
}

table Weapon {
  name:string;
  damage:short;
}

root_type Monster;
`;

struct FbSchema {
  string fileName;
  string packageName;
  string[] includes;

  struct Metadata {
    string ident;
    string value;
  }

  struct Enum {
    string ident;
    string type;
    int[string] values;
    Metadata[] metadata;
  }

  Enum[] enums;

  // TODO union.

  struct Table {
    string name;

    struct Field {
      string name;
      string type;
      string scalar;
      Metadata[] metadata;
    }
  }
}

import std.ascii;
enum wordPattern = std.ascii.letters ~ std.ascii.digits ~ `_.\-`;
enum pathPattern = wordPattern ~ `/`;

string[] builtinTypeId = [
  "bool", "byte", "ubyte", "short", "ushort", "int", "uint",
  "float", "long", "ulong", "double", "int8", "uint8", "int16",
  "uint16", "int32", "uint32", "int64", "uint64", "float32",
  "float64", "string",
];

/*
  EBNF from https://flatbuffers.dev/grammar/

  schema = include* ( namespace_decl | type_decl | enum_decl | root_decl |
           file_extension_decl | file_identifier_decl |
           attribute_decl | rpc_decl | object )*
 */
