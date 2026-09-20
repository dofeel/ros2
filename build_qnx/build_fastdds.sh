#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${WS_DIR}"

echo "=========================================================="
echo " [Phase 1] Building Fast-DDS for QNX 8.0 (AArch64)"
echo " Workspace: ${WS_DIR}"
echo "=========================================================="

# Ensure patches are applied
if [ -f "${SCRIPT_DIR}/apply_patches.sh" ]; then
    bash "${SCRIPT_DIR}/apply_patches.sh"
fi

TOOLCHAIN_FILE="${WS_DIR}/build_qnx/aarch64-qnx8.0-toolchain.cmake"
if [ ! -f "${TOOLCHAIN_FILE}" ]; then
    echo "Error: Toolchain file not found at ${TOOLCHAIN_FILE}"
    exit 1
fi

colcon build \
  --base-paths src \
  --merge-install \
  --packages-up-to fastdds \
  --cmake-args \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DCOMPILE_TOOLS=OFF \
    -DHAVE_INOTIFY=OFF \
    -DHAVE_SYS_INOTIFY_H=0 \
    -DTHIRDPARTY=ON \
    -DOPENSSL_ROOT_DIR="${QNX_TARGET:-/root/ros2_ws/qnx800/target/qnx}/aarch64le/usr" \
    -DOPENSSL_INCLUDE_DIR="${QNX_TARGET:-/root/ros2_ws/qnx800/target/qnx}/usr/include" \
    -DCMAKE_VERBOSE_MAKEFILE=ON

echo "=========================================================="
echo " [Phase 1] Fast-DDS build completed successfully!"
echo "=========================================================="
