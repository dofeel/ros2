#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${WS_DIR}"

echo "=========================================================="
echo " [Phase 2] Building ROS 2 Core System for QNX 8.0 (AArch64)"
echo " Workspace: ${WS_DIR}"
echo "=========================================================="

TOOLCHAIN_FILE="${WS_DIR}/build_qnx/aarch64-qnx8.0-toolchain.cmake"
if [ ! -f "${TOOLCHAIN_FILE}" ]; then
    echo "Error: Toolchain file not found at ${TOOLCHAIN_FILE}"
    exit 1
fi

PARALLEL_JOBS="${PARALLEL_JOBS:-32}"

colcon build \
  --merge-install \
  --parallel-workers "${PARALLEL_JOBS}" \
  --packages-ignore \
    osrf_testing_tools_cpp \
    performance_test_fixture \
    google_benchmark_vendor \
    cyclonedds \
    python_qt_binding \
    qt_gui_cpp \
    mimick_vendor \
    rviz_ogre_vendor \
    lttngpy \
    rttest \
    rosidl_buffer_py \
    gz_math_vendor \
    zenoh_cpp_vendor \
    zenoh_security_tools \
    rmw_zenoh_cpp \
    rmw_test_fixture_implementation \
    resource_retriever \
    rviz_rendering \
    rclpy \
    tf2_py \
    rqt_gui_cpp \
    resource_retriever_service_plugin \
    intra_process_demo \
    turtlesim \
    image_tools \
    test_osrf_testing_tools_cpp \
    image_transport \
    point_cloud_transport \
    image_transport_py \
    point_cloud_transport_py \
    rviz_common \
    tf2_bullet \
    rviz_visual_testing_framework \
    rviz_default_plugins \
    rviz2 \
    rosbag2_py \
    rosbag2_examples_cpp \
    rosbag2_performance_benchmarking \
    rosidl_generator_py \
    rmw_connextdds \
    rmw_connextdds_common \
    rmw_connextddsmicro \
    rti_connext_dds_cmake_module \
  --cmake-args \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_BUILD_PARALLEL_LEVEL="${PARALLEL_JOBS}" \
    -DTRACETOOLS_DISABLED=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DCOMPILE_TOOLS=OFF \
    -DHAVE_INOTIFY=OFF \
    -DHAVE_SYS_INOTIFY_H=0 \
    -DTHIRDPARTY=ON \
    -DCMAKE_BUILD_RPATH="${WS_DIR}/install/lib;${WS_DIR}/install/opt/console_bridge_vendor/lib;${WS_DIR}/install/opt/spdlog_vendor/lib;${WS_DIR}/install/opt/gz_utils_vendor/lib" \
    -DCMAKE_INSTALL_RPATH="${WS_DIR}/install/lib;${WS_DIR}/install/opt/console_bridge_vendor/lib;${WS_DIR}/install/opt/spdlog_vendor/lib;${WS_DIR}/install/opt/gz_utils_vendor/lib"

# Consolidate vendor shared libraries into install/lib for easy deployment
if [ -d "${WS_DIR}/install/opt" ]; then
    echo "Consolidating vendor libraries from install/opt into install/lib..."
    find "${WS_DIR}/install/opt" -name "*.so*" -exec cp -d -P {} "${WS_DIR}/install/lib/" \; 2>/dev/null || true
fi

echo "=========================================================="
echo " [Phase 2] ROS 2 Core build completed successfully!"
echo "=========================================================="
