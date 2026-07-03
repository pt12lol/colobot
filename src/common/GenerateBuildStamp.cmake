# DEBUG | DEVELOPMENT | REMOVEME (whole file)
# Runs at BUILD time (via `cmake -P`) so the timestamp reflects each build,
# unlike configure_file which only runs when CMake reconfigures.
# Expects -DOUT=<path to generated header>.
string(TIMESTAMP BUILD_TS "%Y-%m-%d %H:%M:%S")
file(WRITE "${OUT}" "#pragma once\n#define COLOBOT_BUILD_STAMP \"${BUILD_TS}\"\n")
# Plain copy so the end-of-build print step (PrintBuildStamp.cmake) can read it.
file(WRITE "${TXT}" "${BUILD_TS}")
