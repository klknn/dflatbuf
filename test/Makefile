flatc.zip:
	wget -O flatc.zip https://github.com/google/flatbuffers/releases/download/v25.9.23/Linux.flatc.binary.clang++-18.zip

flatc: flatc.zip
	unzip flatc.zip

# https://flatbuffers.dev/flatc/
monsterdata.bin: monsterdata.json
	./flatc --binary monster.fbs monsterdata.json

monsterdata_simple.bin: monsterdata_simple.json
	./flatc --binary monster.fbs monsterdata_simple.json
