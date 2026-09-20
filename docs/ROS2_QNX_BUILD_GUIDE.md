# ROS 2 (Lyrical / Rolling) QNX 8.0 (AArch64) 交叉编译全流程与避坑指南

本文档记录了在 Linux (x86_64) Docker 编译环境中，使用 QNX SDP 8.0 交叉编译工具链构建完整 **ROS 2 核心系统 (C/C++ Runtime)** 的环境配置、代码准备、补丁说明、构建步骤以及所有关键问题的详细排查与复盘。

---

## 1. 编译环境与目标规格

| 项目 | 说明 |
| :--- | :--- |
| **宿主开发环境** | Ubuntu 22.04 / 24.04 (x86_64) Docker 容器 |
| **目标操作系统** | QNX Neutrino RTOS 8.0.0 (`aarch64le`) |
| **交叉编译器** | QNX `qcc` / `q++`（GCC 后端驱动 + LLVM `libc++` 运行时） |
| **构建管理工具** | `colcon` + `cmake` (3.28+) |
| **默认 DDS 实现** | eProsima Fast-DDS (3.6.x) |
| **目标构架范围** | ROS 2 C/C++ 核心（`rclcpp`, `rmw_fastrtps_cpp`, `tf2`, `urdf`, `rosbag2_storage`, `camera_calibration_parsers` 等） |
| **排除范围** | Python 运行时模块（`rclpy`, `tf2_py` 等）、桌面 GUI（`rviz2`, `rqt`）及 Linux 专有跟踪工具（`lttngpy`） |

---

## 2. 源码仓库准备与依赖拓展

除了标准的 `ros2.repos` 上游仓库外，QNX 目标环境缺失部分基础依赖库，需要额外补齐以下仓库至 `src/`：

1. **`src/eigen`** (`https://gitlab.com/libeigen/eigen.git`, 分支 `3.4`)
   - 线性代数库，为 `orocos_kdl`、`tf2_eigen` 提供底层支持。通过添加 `package.xml` 交由 colcon 管理。
2. **`src/libyaml`** (`https://github.com/yaml/libyaml.git`, 标签 `0.2.5`)
   - YAML C 解析库，为 `rcl_yaml_param_parser` 提供支持。
3. **`src/yaml-cpp`** (`https://github.com/jbeder/yaml-cpp.git`, 标签 `0.8.0`)
   - YAML C++ 解析库，为 `camera_calibration_parsers` 和 `rosbag2_storage` 提供支持。
4. **`src/tinyxml2`** (`https://github.com/leethomason/tinyxml2.git`, 分支 `master`)
   - XML 解析器，为 `urdfdom` 提供支持。
5. **`src/orocos_kinematics_dynamics`** (`https://github.com/orocos/orocos_kinematics_dynamics.git`, 分支 `master`)
   - 运动学与动力学计算库。

> **提示**：所有独立仓库信息均已汇总固化在 `ros2.repos` 中。

---

## 3. QNX 补丁集说明 (`build_qnx/qnx_patches/`)

针对 QNX 8.0 与 Linux 的系统差异，工作空间制作了以下标准化补丁，均可通过 `build_qnx/apply_patches.sh` 脚本一键应用：

| 补丁文件 | 适用仓库 | 修复主要问题 |
| :--- | :--- | :--- |
| `01_fastdds_qnx.patch` | `src/eProsima/Fast-DDS` | 适配 CMake FindThreads，消除警告即错误 (`-Werror`)，适配 TinyXML2 头文件搜索 |
| `02_fastcdr_qnx.patch` | `src/eProsima/Fast-CDR` | 增加 QNX 平台宏定义 `_QNX_SOURCE` |
| `fastdds_submodule_asio_qnx.patch` | `Fast-DDS/thirdparty/asio` | 屏蔽 QNX 不支持的 `SA_RESTART`，适配 `CMSG_ALIGN` 宏及多播套接字 |
| `fastdds_submodule_tinyxml2_qnx.patch` | `Fast-DDS/thirdparty/tinyxml2` | 适配 include 路径导出 |
| `fastdds_submodule_googletest_qnx.patch`| `googletest` | 适配 QNX 线程与系统头文件 |
| `03_rcutils_qnx.patch` | `src/ros2/rcutils` | 禁用 glibc 强制检测；在 `memrchr` 处添加 QNX 平台回退算法 |
| `04_rcl_qnx.patch` | `src/ros2/rcl` | 替换 QNX 不支持的 POSIX 2008 extended locale (`newlocale`, `locale_t`) 为标准 `strtod` |
| `05_rclcpp_qnx.patch` | `src/ros2/rclcpp` | 修复 GCC 语法下 `[[deprecated]]` 与 `RCLCPP_PUBLIC` 混用时的属性解析错误 |
| `06_ros2_tracing_qnx.patch` | `src/ros2/ros2_tracing` | 在 QNX 平台上默认开启 `TRACETOOLS_DISABLED=ON`，生成桩库避免依赖 LTTng-UST |
| `07_yaml_cpp_vendor_qnx.patch` | `src/ros2/yaml_cpp_vendor` | 完善 CMake Target 别名，使 `yaml-cpp` 与 `yaml-cpp::yaml-cpp` 均可用 |
| `08_yaml_cpp_qnx.patch` | `src/yaml-cpp` | 关闭测试与解析工具构建，纯净导出共享库 |
| `extra_files/*.xml` | `eigen`, `libyaml`, `yaml-cpp` | 提供基础 `package.xml` 声明，使 colcon 能正确定位编译顺序 |

---

## 4. 两阶段构建流程

由于 Fast-DDS 为下层 RMW 中间件的基础，当前标准构建流程拆分为两阶段执行。

### 阶段 1：编译 Fast-DDS 中间件
直接运行脚本：
```bash
bash build_qnx/build_fastdds.sh
```
底层执行命令：
```bash
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

### 阶段 2：编译 ROS 2 核心组件
直接运行脚本：
```bash
bash build_qnx/build_ros2.sh
```
底层执行命令：
```bash
colcon build \
  --merge-install \
  --parallel-workers 32 \
  --packages-ignore \
    osrf_testing_tools_cpp performance_test_fixture google_benchmark_vendor \
    cyclonedds python_qt_binding qt_gui_cpp mimick_vendor rviz_ogre_vendor \
    lttngpy rttest rosidl_buffer_py gz_math_vendor zenoh_cpp_vendor \
    zenoh_security_tools rmw_zenoh_cpp rmw_test_fixture_implementation \
    resource_retriever rviz_rendering rclpy tf2_py rqt_gui_cpp \
    resource_retriever_service_plugin intra_process_demo turtlesim \
    image_tools test_osrf_testing_tools_cpp image_transport point_cloud_transport \
    image_transport_py point_cloud_transport_py rviz_common tf2_bullet \
    rviz_visual_testing_framework rviz_default_plugins rviz2 rosbag2_py \
    rosbag2_examples_cpp rosbag2_performance_benchmarking rosidl_generator_py \
    rmw_connextdds rmw_connextdds_common rmw_connextddsmicro rti_connext_dds_cmake_module \
  --cmake-args \
    -DCMAKE_TOOLCHAIN_FILE=$(pwd)/aarch64-qnx8.0-toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_BUILD_PARALLEL_LEVEL=32 \
    -DTRACETOOLS_DISABLED=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DCOMPILE_TOOLS=OFF \
    -DHAVE_INOTIFY=OFF \
    -DHAVE_SYS_INOTIFY_H=0 \
    -DTHIRDPARTY=ON \
    -DCMAKE_BUILD_RPATH="$(pwd)/install/lib;$(pwd)/install/opt/console_bridge_vendor/lib;$(pwd)/install/opt/spdlog_vendor/lib;$(pwd)/install/opt/gz_utils_vendor/lib" \
    -DCMAKE_INSTALL_RPATH="$(pwd)/install/lib;$(pwd)/install/opt/console_bridge_vendor/lib;$(pwd)/install/opt/spdlog_vendor/lib;$(pwd)/install/opt/gz_utils_vendor/lib"
```

### 一键全自动构建脚本
```bash
bash build_qnx/build_all.sh
```

---

## 5. 关键疑难排查与复盘 (Troubleshooting)

### 问题 1：`rcutils` 提示 `undefined reference to memrchr`
- **现象**：`pluginlib` 链接 `librcutils.so` 时报 `memrchr` 未定义。
- **原因**：QNX Neutrino C 库未实现 GNU 扩展函数 `memrchr`，且 CMake 的 glibc 检查因返回值解析问题在 QNX 上被误判。
- **解决**：在 `rcutils/src/find.c` 中显式排查 `__QNX__`，走便携式的向后遍历查找回退分支；在 `CMakeLists.txt` 中对 QNX 禁用 glibc 检测。

### 问题 2：`rcl_yaml_param_parser` 提示 `locale_t` / `newlocale` 未定义
- **现象**：C 源码编译报错 `unknown type name 'locale_t'`。
- **原因**：QNX C 库尚未完全实现 POSIX.1-2008 的扩展区域本地化接口。由于 QNX 默认数字转换本来就是标准 C locale，无需线程级独立切换。
- **解决**：在 `rcl_yaml_param_parser/src/parse.c` 中添加 `#elif defined(__QNX__)` 分支，直接调用标准 `strtod(nptr, endptr)`。

### 问题 3：`kdl_parser` 提示 `EIGEN3_INCLUDE_DIR NOTFOUND`
- **现象**：构建 `orocos_kdl` 时提示找不到 Eigen3 头文件。
- **原因**：QNX 系统镜像中未预置 Eigen3，且 `python_orocos_kdl` 尝试查找 Host/Target Python 导致混淆。
- **解决**：将 Eigen 3.4 源码拉入 `src/eigen`，添加 `package.xml` 作为 colcon 优先构建包；在 `python_orocos_kdl` 下放置 `COLCON_IGNORE` 忽略 Python 绑定。

### 问题 4：`rmw_connextdds_common` 提示找不到 `tracetools`
- **现象**：`tracetools` 未生成 CMake 导出文件。
- **原因**：`tracetools` 默认强依赖 Linux LTTng-UST 跟踪套件，而 QNX 平台无此机制。
- **解决**：修改 `tracetools/CMakeLists.txt`，在 QNX 下默认启用 `TRACETOOLS_DISABLED=ON`，生成桩函数（stub）动态库供下游链接。

### 问题 5：`rclcpp` 提示 `expected identifier before '__attribute__'`
- **现象**：编译 `rclcpp/include/rclcpp/memory_strategy.hpp` 报错。
- **原因**：GCC 解析带有跨平台宏声明的类时，若将 C++11 标准属性 `[[deprecated(...)]]` 夹在 `class` 与 `RCLCPP_PUBLIC` 中间会触发语法树歧义。
- **解决**：在 GCC/Clang 下改用传统的 `class __attribute__((deprecated(...))) RCLCPP_PUBLIC MemoryStrategy` 声明。

### 问题 6：`camera_calibration_parsers` 找不到 `yaml-cpp`
- **现象**：`Findyaml-cpp.cmake` 报 `Could NOT find yaml-cpp (missing: YAML_PKG_CONFIG_FOUND)`。
- **原因**：现代 ROS 2 `yaml_cpp_vendor` 不再内置源码下载，而是要求环境提供 `yaml-cpp`。QNX SDP 无自带二进制。
- **解决**：拉取 `yaml-cpp 0.8.0` 至 `src/yaml-cpp` 并配置 `package.xml`，关闭单元测试，输出共享库。

### 问题 7：`tf2_ros` 提示 `libconsole_bridge.so.1.0 not found`
- **现象**：`static_transform_publisher` 报 `undefined reference to console_bridge::log`。
- **原因**：
  1. `console_bridge_vendor` 将库安装在 `install/opt/console_bridge_vendor/lib` 隔离路径下。
  2. GNU ld 的规范规定：**一旦命令行中存在 `-rpath-link`，链接器解析间接依赖时将忽略所有 `-rpath` 选项**。
  3. `aarch64-qnx8.0-toolchain.cmake` 中使用了 `CACHE ... FORCE` 覆盖了 `CMAKE_EXE_LINKER_FLAGS`。
- **解决**：
  - 改造 toolchain 中的 `RPATH_LINK_STRING` 机制，使其自动继承提取 `--cmake-args` 中的 `CMAKE_BUILD_RPATH` / `CMAKE_INSTALL_RPATH` 并同步至 `-Wl,-rpath-link`。
  - 构建完成后由脚本自动将 `install/opt/*/lib` 下的动态库同步软链至 `install/lib`，确保上板部署零障碍。

---

## 6. 目标机 (QNX AArch64) 运行与部署指南

### 1. 打包安装产物
在编译机工作空间根目录下执行：
```bash
cd /root/ros2_ws
tar -czvf ros2_qnx_install.tar.gz install/
```

### 2. 复制至 QNX 开发板
通过 scp 发送压缩包并解压（假设部署到开发板 `/opt/ros2` 目录）：
```bash
# 开发板端执行
mkdir -p /opt/ros2
tar -xzvf ros2_qnx_install.tar.gz -C /opt/ros2
```

### 3. 配置运行环境变量
编译阶段已自动将专为 QNX Neutrino RTOS 深度优化的设备端环境脚本安装至 `install/setup_qnx.sh`。
该脚本完全兼容 POSIX `/bin/sh` 与 QNX 默认的 Korn Shell (`/bin/ksh`)，能自适应安装路径，并自动加载动态库与 Ament 索引：

```sh
# 进入解压目录并生效环境（POSIX sh / ksh 支持点命令或 source）
. /opt/ros2/install/setup_qnx.sh

# 如部署在非标准路径且自动探测受限，可手动显式指定：
# export ROS2_INSTALL_DIR=/your/custom/install/path
# . /your/custom/install/path/setup_qnx.sh
```

### 4. 验证节点通信
- **终端 1 启动发布者**：
  ```sh
  . /opt/ros2/install/setup_qnx.sh
  talker
  ```
- **终端 2 启动订阅者**：
  ```sh
  . /opt/ros2/install/setup_qnx.sh
  listener
  ```
若两端正常收发消息，即代表 QNX 8.0 上的 ROS 2 核心通信栈运行成功！
