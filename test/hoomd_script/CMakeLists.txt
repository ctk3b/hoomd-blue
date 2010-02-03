# $Id$
# $ $URL$
# Maintainer: joaander

# setup hoomd runner environment
if (ENABLE_STATIC)
    # static builds need to run the built hoomd target
    get_target_property(HOOMD_STATIC_EXE hoomd LOCATION)
    set(HOOMD_RUN_EXE ${HOOMD_STATIC_EXE})
else (ENABLE_STATIC)
    # shared lib builds need to run the configured hoomd_run script
    get_target_property(LIBHOOMD_LOCATION libhoomd LOCATION)
    get_filename_component(LIBHOOMD_DIR ${LIBHOOMD_LOCATION} PATH)
    
    set(HOOMD_RUN_EXE ${HOOMD_BINARY_DIR}/python-runner/hoomd_run)
endif (ENABLE_STATIC)

#############################
# macro for adding hoomd script tests
macro(add_hoomd_script_test test_py)
# name the test
get_filename_component(_test_name ${test_py} NAME_WE)

if (CMAKE_MINOR_VERSION GREATER 7 AND ENABLE_STATIC)
# with CMake 2.8.x and newer, use the NAME COMMAND form of add test to run the built hoomd target
# (in static builds)
add_test(NAME script-${_test_name}-cpu COMMAND hoomd ${test_py} "--mode=cpu")
if (ENABLE_CUDA)
add_test(NAME script-${_test_name}-gpu COMMAND hoomd ${test_py} "--mode=gpu")
endif (ENABLE_CUDA)

else (CMAKE_MINOR_VERSION GREATER 7 AND ENABLE_STATIC)
# with CMake 2.6.x, or shared builds use the old form of add_test to add a specific hoomd_run exename
add_test(script-${_test_name}-cpu ${HOOMD_RUN_EXE} ${test_py} "--mode=cpu")
if (ENABLE_CUDA)
add_test(script-${_test_name}-gpu ${HOOMD_RUN_EXE} ${test_py} "--mode=gpu")
endif (ENABLE_CUDA)

endif (CMAKE_MINOR_VERSION GREATER 7 AND ENABLE_STATIC)
endmacro(add_hoomd_script_test)
###############################

# loop through all test_*.py files
file(GLOB _hoomd_script_tests ${CMAKE_CURRENT_SOURCE_DIR}/test_*.py)

foreach(test ${_hoomd_script_tests})
add_hoomd_script_test(${test})
endforeach(test)
