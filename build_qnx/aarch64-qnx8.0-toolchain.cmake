# ===== Platform =====
set(CMAKE_SYSTEM_NAME QNX)
set(CMAKE_SYSTEM_VERSION 8.0.0)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(QNX TRUE)

# 读取 QNX SDP 环境变量
set(QNX_HOST $ENV{QNX_HOST})
set(QNX_TARGET $ENV{QNX_TARGET})

# ===== Compiler =====
# Using qcc/q++ directly as they are in PATH
set(CMAKE_C_COMPILER qcc)
set(CMAKE_CXX_COMPILER q++)

# Make sure assembly is also compiled via the QNX cross toolchain.
# If not set, CMake may fall back to the host assembler, which cannot assemble AArch64 code.
set(CMAKE_ASM_COMPILER qcc)

# ===== qcc target profile =====
set(QNX_TARGET_PROFILE "-Vgcc_ntoaarch64le")

# C / C++
set(CMAKE_C_FLAGS_INIT   "${QNX_TARGET_PROFILE}")
set(CMAKE_CXX_FLAGS_INIT "${QNX_TARGET_PROFILE} -std=c++17 -stdlib=libc++")

# ASM (treat .S as preprocessed assembly)
set(CMAKE_ASM_FLAGS_INIT "${QNX_TARGET_PROFILE} -x assembler-with-cpp")

# ===== sysroot =====
set(CMAKE_SYSROOT $ENV{QNX_TARGET})
# Add ~/ros2_ws/appsdk to search path so find_package/find_library works
set(CMAKE_FIND_ROOT_PATH $ENV{QNX_TARGET} ~/ros2_ws/install)
# ===== sysroot & find root =====
set(CMAKE_SYSROOT $ENV{QNX_TARGET})

# 将 aarch64le 相关路径加入 CMAKE_FIND_ROOT_PATH 与 CMAKE_SYSTEM_LIBRARY_PATH
list(APPEND CMAKE_FIND_ROOT_PATH
  $ENV{QNX_TARGET}/aarch64le
  $ENV{QNX_TARGET}/aarch64le/usr
)

list(APPEND CMAKE_SYSTEM_LIBRARY_PATH
  $ENV{QNX_TARGET}/aarch64le/lib
  $ENV{QNX_TARGET}/aarch64le/usr/lib
)


# ===== Find root =====
# 严禁搜索 Host 宿主机系统的库和头文件
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# ===== Common compile flags =====
set(COMMON_FLAGS "${QNX_TARGET_PROFILE} -Wall -Wextra -Wno-unused-parameter -Wno-error=maybe-uninitialized -Wno-array-bounds -Wno-stringop-overflow -Wno-free-nonheap-object -fPIC")
set(COMMON_DEFINES "-D_QNX_SOURCE -D__QNX800__")

# C flags
set(CMAKE_C_FLAGS "${COMMON_FLAGS} ${COMMON_DEFINES} -D_POSIX_C_SOURCE=200112L" CACHE STRING "C flags" FORCE)
set(CMAKE_C_FLAGS_DEBUG "-g -Og" CACHE STRING "C debug flags" FORCE)
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG" CACHE STRING "C release flags" FORCE)

# C++ flags
set(CMAKE_CXX_FLAGS "${COMMON_FLAGS} ${COMMON_DEFINES} -D_POSIX_C_SOURCE=200112L" CACHE STRING "C++ flags" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG "-g -Og" CACHE STRING "C++ debug flags" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG" CACHE STRING "C++ release flags" FORCE)

# If CMAKE_BUILD_RPATH or CMAKE_INSTALL_RPATH is passed via cmake-args, automatically append to RPATH_LINK_STRING
if(DEFINED CMAKE_BUILD_RPATH AND NOT CMAKE_BUILD_RPATH STREQUAL "")
  string(REPLACE ";" ":" _EXTRA_BUILD_RPATH "${CMAKE_BUILD_RPATH}")
  set(RPATH_LINK_STRING "${_EXTRA_BUILD_RPATH}:${RPATH_LINK_STRING}")
endif()
if(DEFINED CMAKE_INSTALL_RPATH AND NOT CMAKE_INSTALL_RPATH STREQUAL "")
  string(REPLACE ";" ":" _EXTRA_INSTALL_RPATH "${CMAKE_INSTALL_RPATH}")
  set(RPATH_LINK_STRING "${_EXTRA_INSTALL_RPATH}:${RPATH_LINK_STRING}")
endif()

if(NOT DEFINED CMAKE_EXE_LINKER_FLAGS OR CMAKE_EXE_LINKER_FLAGS STREQUAL "")
  set(CMAKE_EXE_LINKER_FLAGS
    "${QNX_TARGET_PROFILE} -Wl,--as-needed,-z,global -Wl,-rpath-link,${RPATH_LINK_STRING}"
    CACHE STRING "Executable linker flags" FORCE
  )
else()
  if(NOT CMAKE_EXE_LINKER_FLAGS MATCHES "-rpath-link")
    set(CMAKE_EXE_LINKER_FLAGS
      "${QNX_TARGET_PROFILE} -Wl,--as-needed,-z,global -Wl,-rpath-link,${RPATH_LINK_STRING} ${CMAKE_EXE_LINKER_FLAGS}"
      CACHE STRING "Executable linker flags" FORCE
    )
  endif()
endif()

if(NOT DEFINED CMAKE_SHARED_LINKER_FLAGS OR CMAKE_SHARED_LINKER_FLAGS STREQUAL "")
  set(CMAKE_SHARED_LINKER_FLAGS
    "${QNX_TARGET_PROFILE} -Wl,--as-needed,-z,global -Wl,-rpath-link,${RPATH_LINK_STRING}"
    CACHE STRING "Shared library linker flags" FORCE
  )
else()
  if(NOT CMAKE_SHARED_LINKER_FLAGS MATCHES "-rpath-link")
    set(CMAKE_SHARED_LINKER_FLAGS
      "${QNX_TARGET_PROFILE} -Wl,--as-needed,-z,global -Wl,-rpath-link,${RPATH_LINK_STRING} ${CMAKE_SHARED_LINKER_FLAGS}"
      CACHE STRING "Shared library linker flags" FORCE
    )
  endif()
endif()

# Release mode: strip debug symbols
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "-Wl,--strip-debug" CACHE STRING "Release executable linker flags" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "-Wl,--strip-debug" CACHE STRING "Release shared library linker flags" FORCE)

# Enable position independent code
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Skip try_run
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_CROSSCOMPILING TRUE)
