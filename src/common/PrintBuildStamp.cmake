# DEBUG | DEVELOPMENT | REMOVEME (whole file)
# Prints the build timestamp written by GenerateBuildStamp.cmake.
# Run as the final step of build-and-install so it shows at the very end.
# Expects -DTXT=<path to build_stamp.txt>.
if(EXISTS "${TXT}")
    file(READ "${TXT}" BUILD_TS)
    message(STATUS "Build timestamp: ${BUILD_TS}")
endif()
