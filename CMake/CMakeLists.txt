# Maintainer: joaander

# Specify cmake modules path to use our custom modules
set(CMAKE_MODULE_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/mpi"
    "${CMAKE_CURRENT_SOURCE_DIR}/thrust"
    "${CMAKE_CURRENT_SOURCE_DIR}/hoomd"
    "${CMAKE_CURRENT_SOURCE_DIR}/git"
    "${CMAKE_MODULE_PATH}"
    PARENT_SCOPE)

# Use built-in FindCUDA.cmake for older versions of cmake
if (CMAKE_VERSION VERSION_LESS 2.8.0)
set(CMAKE_MODULE_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/cuda"
    "${CMAKE_MODULE_PATH}"
    PARENT_SCOPE)
endif()

## install the helper modules in linux and mac
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/cuda
                  ${CMAKE_CURRENT_SOURCE_DIR}/thrust
                  ${CMAKE_CURRENT_SOURCE_DIR}/hoomd
                  ${CMAKE_CURRENT_SOURCE_DIR}/git
        DESTINATION ${DATA_INSTALL_DIR}/CMake
        PATTERN ".svn" EXCLUDE
        )
