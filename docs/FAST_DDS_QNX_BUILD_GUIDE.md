# QNX 8.0 (AArch64) 平台 Fast-DDS 交叉编译总结与避坑指南

本文档总结了在 Linux (x86_64) Docker 容器中，使用 QNX SDP 8.0 工具链交叉编译 ROS 2 核心中间件 **Fast-DDS (3.6.x)** 的全过程、环境准备、前置补丁、遇到的核心问题、根本原因分析以及最终的解决方案。

---

## 1. 编译环境与目标信息

- **宿主环境**：Linux x86_64 (Ubuntu Docker 容器，容器名 `ros2_lyrical_env`)
- **目标平台**：QNX Neutrino RTOS 8.0.0 (aarch64le)
- **编译驱动/工具链**：QNX `qcc` / `q++` (GCC 后端 + LLVM `libc++`)
- **构建工具**：`colcon` + `cmake` (4.x / 3.28+)
- **工具链文件**：`aarch64-qnx8.0-toolchain.cmake`
- **核心组件版本**：Fast-DDS 3.6.x，Fast-CDR 2.x，Asio (Thirdparty)，TinyXML2 (Thirdparty)

---

## 2. 源码准备与前置打补丁（Pre-build Setup）

在开始编译前，需要先下载并初始化 Fast-DDS 的依赖子模块（Asio, Fast-CDR, TinyXML2 等），并打上 QNX 适配补丁，同时准备 `foonathan_memory_vendor` 与 `googletest`：

```bash
# 进入 Fast-DDS 源码目录（例如 src/eProsima/Fast-DDS）
cd src/eProsima/Fast-DDS
WORKSPACE=$PWD

# 1. 初始化并更新第三方子模块 (thirdparty submodules)
git submodule update --init $WORKSPACE/thirdparty/asio/ $WORKSPACE/thirdparty/fastcdr $WORKSPACE/thirdparty/tinyxml2/

# 2. 为 Asio 应用 QNX 补丁
cd $WORKSPACE/thirdparty/asio
git apply $WORKSPACE/build_qnx/qnx_patches/asio_qnx.patch

# 3. 为 Fast-CDR 应用 QNX 补丁
cd $WORKSPACE/thirdparty/fastcdr
git apply $WORKSPACE/build_qnx/qnx_patches/fastcdr_qnx.patch

# 4. 为 TinyXML2 应用 QNX 补丁
# 注意：TinyXML2 的 CMakeLists.txt 使用了 CRLF 换行符，需先通过 unix2dos 转换补丁文件的换行符再执行 apply
cd $WORKSPACE/thirdparty/tinyxml2
unix2dos $WORKSPACE/build_qnx/qnx_patches/tinyxml2_qnx.patch
git apply $WORKSPACE/build_qnx/qnx_patches/tinyxml2_qnx.patch

# 5. 克隆 foonathan_memory_vendor 依赖
cd $WORKSPACE
git clone https://github.com/eProsima/foonathan_memory_vendor.git

# 6. 克隆并为 googletest 打 QNX 补丁
cd $WORKSPACE
git clone https://github.com/google/googletest.git && cd googletest
git checkout v1.13.0
git apply $WORKSPACE/build_qnx/qnx_patches/googletest_qnx.patch
```

---

## 3. 最终成功的编译命令

在 Docker 容器内的 ROS 2 工作空间根目录（`/root/ros2_ws`）执行：

```bash
# 1. 首次或修改 CMake 配置后，建议先清理缓存
rm -rf build/fastdds

# 2. 执行交叉编译
colcon build \
  --base-paths src \
  --merge-install \
  --packages-up-to fastdds \
  --cmake-args \
    -DCMAKE_TOOLCHAIN_FILE=$(pwd)/aarch64-qnx8.0-toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DCOMPILE_TOOLS=OFF \
    -DHAVE_INOTIFY=OFF \
    -DHAVE_SYS_INOTIFY_H=0 \
    -DTHIRDPARTY=ON \
    -DOPENSSL_ROOT_DIR=/root/ros2_ws/qnx800/target/qnx/aarch64le/usr \
    -DOPENSSL_INCLUDE_DIR=/root/ros2_ws/qnx800/target/qnx/usr/include \
    -DCMAKE_VERBOSE_MAKEFILE=ON
```

### 关键参数解析：
- `--base-paths src`：限定 colcon 仅扫描 `src/` 目录，防止非源码目录（如外部 SDK `appsdk`）被识别为 ROS 包而引发构建失败。
- `-DCMAKE_TOOLCHAIN_FILE=...`：指定 QNX aarch64 交叉编译工具链。
- `-DTHIRDPARTY=ON`：启用 Fast-DDS 内置的第三方依赖子模块（Asio、TinyXML2 等）。
- `-DHAVE_INOTIFY=OFF -DHAVE_SYS_INOTIFY_H=0`：QNX 系统无 Linux inotify 特性，显式禁用。
- `-DOPENSSL_ROOT_DIR / -DOPENSSL_INCLUDE_DIR`：指定 QNX SDP 预置的 OpenSSL 头文件及库路径。

---

## 4. 踩坑记录与解决方案复盘

在编译过程中共解决了 **5 个关键问题**，涵盖了包扫描、Sysroot 路径检索、编译器模板分析误报、链接期符号定位等各个阶段。

---

### 问题一：外部预编译 `appsdk` 被误识别为待构建包
#### 1. 现象
执行 `colcon build` 时，首个失败任务为 `optee-client-headers`：
```text
CMake Error at CMakeLists.txt:16 (target_include_directories):
  Cannot specify include directories for target "teec" which is not built by this project.
CMake Error at CMakeLists.txt:25 (install):
  install FILES given no DESTINATION!
```
#### 2. 原因分析
工作空间中的 `appsdk/include/CMakeLists.txt` 定义了一个用于导出头文件的项目 `optee-client-headers`。colcon 默认递归扫描整个工作空间目录，将其当成了待构建的源码包。而该 CMake 脚本自身存在 target 命名错误（写成了 `teec`）以及未引入 `GNUInstallDirs` 导致 `CMAKE_INSTALL_INCLUDEDIR` 为空。
#### 3. 解决方案
- **推荐方案**：运行 colcon 时增加 `--base-paths src`，只编译 `src/` 下的代码；
- **备用方案**：在 `appsdk` 目录下创建忽略标记：
  ```bash
  touch appsdk/COLCON_IGNORE
  ```

---

### 问题二：TinyXML2 头文件找不到 (`fatal error: tinyxml2.h`)
#### 1. 现象
```text
/root/ros2_ws/src/eProsima/Fast-DDS/src/cpp/xmlparser/XMLEndpointParser.h:29:10: fatal error: tinyxml2.h: No such file or directory
   29 | #include <tinyxml2.h>
```
#### 2. 原因分析
- 传入 `-DTHIRDPARTY=ON` 后，Fast-DDS 激活了 `thirdparty/tinyxml2` 源码模块。
- 原 `cmake/modules/FindTinyXML2.cmake` 中查找头文件使用了：
  ```cmake
  find_path(TINYXML2_INCLUDE_DIR NAMES tinyxml2.h NO_CMAKE_FIND_ROOT_PATH)
  ```
  `NO_CMAKE_FIND_ROOT_PATH` 导致 CMake 跳出了 QNX 目标目录，而在宿主机 Linux 系统的 `/usr/include` 下找到了宿主机的 `tinyxml2.h`，将其记录为 `/usr/include`。
- 在 QNX 交叉编译下，CMake 会**主动剔除隐式宿主系统路径（如 `-I/usr/include`）**以防环境污染。最终传递给 `q++` 的编译选项中没有任何包含 `tinyxml2.h` 的路径，导致编译报错。

---

### 问题三：Sysroot 重定向导致第三方子模块无法检索 (`Could NOT find TinyXML2`)
#### 1. 现象
```text
CMake Error at /usr/share/cmake-4.2/Modules/FindPackageHandleStandardArgs.cmake:290 (message):
  Could NOT find TinyXML2 (missing: TINYXML2_SOURCE_DIR TINYXML2_INCLUDE_DIR)
```
#### 2. 原因分析
在尝试限制 `find_path` 仅在 `PATHS ${PROJECT_SOURCE_DIR}/thirdparty/tinyxml2` 查找时，若漏掉了 `NO_CMAKE_FIND_ROOT_PATH`：
- Toolchain 设置了 `set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)`；
- CMake 会将指定的源码相对路径自动加上 Sysroot 前缀（变成 `${QNX_TARGET}/...`）进行重定位搜索，导致源码树中的子模块无法被命中。

#### 3. 问题二与问题三的最终解决方案
修改 `src/eProsima/Fast-DDS/cmake/modules/FindTinyXML2.cmake`，组合使用 `NO_DEFAULT_PATH` 与 `NO_CMAKE_FIND_ROOT_PATH`：
```cmake
if(TINYXML2_FROM_THIRDPARTY OR ANDROID)
    set(TINYXML2_FROM_SOURCE ON)
    find_path(TINYXML2_INCLUDE_DIR NAMES tinyxml2.h
        PATHS ${PROJECT_SOURCE_DIR}/thirdparty/tinyxml2
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH)
else()
    find_path(TINYXML2_INCLUDE_DIR NAMES tinyxml2.h)
endif()

if(TINYXML2_FROM_SOURCE)
    find_path(TINYXML2_SOURCE_DIR NAMES tinyxml2.cpp
        PATHS ${PROJECT_SOURCE_DIR}/thirdparty/tinyxml2
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH)
else()
    find_library(TINYXML2_LIBRARY tinyxml2)
endif()
```
- `NO_DEFAULT_PATH`：禁止搜索宿主机 `/usr/include`。
- `NO_CMAKE_FIND_ROOT_PATH`：允许跳出 QNX Sysroot 寻找源码树内的 `thirdparty/tinyxml2`。

---

### 问题四：GCC 与 LLVM libc++ 模板在 `-O3` 下的误判警告及 `-Werror`
#### 1. 现象
```text
error: array subscript 1 is outside array bounds of 'eprosima::fastdds::rtps::CacheChange_t [0]' [-Werror=array-bounds]
error: writing 8 bytes into a region of size 0 [-Werror=stringop-overflow=]
error: 'void operator delete(void*)' called on pointer '<unknown>' with nonzero offset [-Werror=free-nonheap-object]
cc1plus: all warnings being treated as errors
```
#### 2. 原因分析
1. **编译器误报**：QNX 8.0 使用 GCC 前端结合 LLVM `libc++`。在 `-O3` 深度内联优化下，GCC 对 `std::vector` 的内存分配、迭代器扩容及析构的静态分析存在已知的误报，分别触发了 `-Warray-bounds`、`-Wstringop-overflow` 和 `-Wfree-nonheap-object`。
2. **为什么会被当作错误（`-Werror`）**：
   Fast-DDS 的 `CMakeLists.txt` 中存在：
   ```cmake
   if (${SANITIZER_THREAD} EQUAL -1 AND NOT QNX)
       set(CMAKE_COMPILE_WARNING_AS_ERROR ON) # 引入 -Werror
   endif()
   ```
   **关键盲点**：CMake 原生只有 `CMAKE_SYSTEM_NAME` 为 `"QNX"`，默认**不会**自动定义变量 `QNX` 为真！因为 `QNX` 为空，`NOT QNX` 判定为真，导致 Fast-DDS 在交叉编译时强行开启了 `CMAKE_COMPILE_WARNING_AS_ERROR ON`。

#### 3. 解决方案
1. **在 `aarch64-qnx8.0-toolchain.cmake` 中显式声明 `QNX` 变量并屏蔽常见误报**：
   ```cmake
   set(CMAKE_SYSTEM_NAME QNX)
   set(CMAKE_SYSTEM_VERSION 8.0.0)
   set(CMAKE_SYSTEM_PROCESSOR aarch64)
   set(QNX TRUE) # 显式置为真

   set(COMMON_FLAGS "${QNX_TARGET_PROFILE} -Wall -Wextra -Wno-unused-parameter -Wno-error=maybe-uninitialized -Wno-array-bounds -Wno-stringop-overflow -Wno-free-nonheap-object -fPIC")
   ```
2. **在 `src/eProsima/Fast-DDS/CMakeLists.txt` 中适配**：
   ```cmake
   project(fastdds VERSION "3.6.2.0" LANGUAGES C CXX)
   
   if(CMAKE_SYSTEM_NAME STREQUAL "QNX")
       set(QNX 1)
   endif()
   ```
   并在编译选项中确保：
   ```cmake
   if(QNX)
       set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-array-bounds -Wno-stringop-overflow -Wno-free-nonheap-object")
   endif()
   ```
   关闭 `-Werror` 并消除误报警告输出。

---

### 问题五：链接期找不到线程库 (`cannot find -lpthreads`)
#### 1. 现象
```text
/root/ros2_ws/qnx800/host/linux/x86_64/usr/bin/aarch64-unknown-nto-qnx8.0.0-ld: cannot find -lpthreads: No such file or directory
gmake[2]: *** [src/cpp/CMakeFiles/fastdds.dir/build.make:4265: src/cpp/libfastdds.so.3.6.2.0] Error 1
```
#### 2. 原因分析
1. **QNX 特性**：QNX 的 POSIX 线程函数（`pthread_*`）直接集成在核心 `libc.so` 中，不需要也不存在 `-lpthreads` 或 `-lpthread`。
2. **静态试编译假阳性**：Toolchain 中启用了 `set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)`，导致 `FindThreads.cmake` 在执行 `CHECK_LIBRARY_EXISTS(pthreads ...)` 时仅用 `ar` 打包了静态库，未调用真实的 `ld`，产生了假阳性判定。
3. Fast-DDS 误以为系统存在独立线程库，将 `CMAKE_THREAD_LIBS_INIT` 设置为了 `-lpthreads`，并在生成 `libfastdds.so` 时传给链接器，最终导致链接失败。

#### 3. 解决方案
修改 `src/eProsima/Fast-DDS/cmake/modules/FindThreads.cmake`：
在检测到 QNX 平台时，直接跳过外部线程库探测，将 `CMAKE_THREAD_LIBS_INIT` 强制置为空：
```diff
  set(CMAKE_HAVE_THREADS_LIBRARY)
+ if(QNX)
+   set(CMAKE_THREAD_LIBS_INIT "")
+   set(CMAKE_HAVE_THREADS_LIBRARY 1)
+   set(Threads_FOUND TRUE)
- if(NOT THREADS_HAVE_PTHREAD_ARG)
+ elseif(NOT THREADS_HAVE_PTHREAD_ARG)
```
并在启用标识处补充：
```diff
-if(CMAKE_THREAD_LIBS_INIT OR CMAKE_HAVE_LIBC_PTHREAD_KILL)
+if(CMAKE_THREAD_LIBS_INIT OR CMAKE_HAVE_LIBC_PTHREAD_KILL OR QNX)
   set(CMAKE_USE_PTHREADS_INIT 1)
   set(Threads_FOUND TRUE)
 endif()
```

---

## 5. 涉及修改的文件清单

| 序号 | 修改文件路径 | 修改目的 |
| :--- | :--- | :--- |
| 1 | `aarch64-qnx8.0-toolchain.cmake` | 补充 `set(QNX TRUE)`；在 `COMMON_FLAGS` 中追加忽略 libc++ 模板警告（`-Wno-array-bounds` 等） |
| 2 | `src/eProsima/Fast-DDS/CMakeLists.txt` | 声明 `QNX 1`，关闭 Warning-as-Error，追加 GCC 警告屏蔽选项 |
| 3 | `src/eProsima/Fast-DDS/cmake/modules/FindTinyXML2.cmake` | 精准定位本地 `thirdparty/tinyxml2` 源码，防止污染宿主机包含路径与 Sysroot 错位 |
| 4 | `src/eProsima/Fast-DDS/cmake/modules/FindThreads.cmake` | 针对 QNX 平台将线程链接库设置为空，避免误链 `-lpthreads` |

---

## 6. 验证与后续维护建议

- **清理机制**：每次修改 Toolchain 或底层 CMake 查找逻辑后，由于 CMake 会持久化缓存（如 `build/fastdds/CMakeCache.txt`），建议使用 `rm -rf build/fastdds` 后再重新构建。
- **扩展性**：在后续编译 ROS 2 其他上层包（如 `rmw_fastrtps_cpp`, `rcl`, `rclcpp` 等）时，Toolchain 中已补充的 `set(QNX TRUE)` 及警告屏蔽参数将持续生效，防止同类交叉编译错误再次发生。
