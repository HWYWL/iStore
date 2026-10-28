# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(PuttyLib)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(LIBS_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a)
set(INCLUDE_ROOT_PATH ${LIBS_ROOT_PATH}/../)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${INCLUDE_ROOT_PATH}/include
                    ${NATIVERENDER_ROOT_PATH}/protocol
                    ${NATIVERENDER_ROOT_PATH}/command
                    )

add_library(entry SHARED 
    napiInterface.cpp 
    napiPortForward.cpp
    napiWrapper.cpp
    napiWrapper.hpp
    key_manager.cpp
    napiSftp.cpp
)

target_link_libraries(entry PUBLIC libace_napi.z.so
                                   libc++_shared.so
                                   libhilog_ndk.z.so
                                   libuv.so
                                   libnet_connection.so
                                   libohenvironment.so
                                   ${LIBS_ROOT_PATH}/libcrypto.a
                                   ${LIBS_ROOT_PATH}/libssl.a
                                   z
                                   ${LIBS_ROOT_PATH}/libssh2.a
                                   )

add_subdirectory(${NATIVERENDER_ROOT_PATH}/protocol)
add_subdirectory(${NATIVERENDER_ROOT_PATH}/jsonAnalyse)
add_subdirectory(${NATIVERENDER_ROOT_PATH}/command)
