#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "##########################################################"
echo "  Full ROS 2 QNX 8.0 (AArch64) Cross-Compilation Workflow"
echo "  Workspace: ${WS_DIR}"
echo "##########################################################"

# Step 1: Apply Patches
echo ""
echo "[Step 1/3] Applying QNX patches..."
bash "${SCRIPT_DIR}/apply_patches.sh"

# Step 2: Build Fast-DDS
echo ""
echo "[Step 2/3] Building Fast-DDS..."
bash "${SCRIPT_DIR}/build_fastdds.sh"

# Step 3: Build ROS 2 Core System
echo ""
echo "[Step 3/3] Building ROS 2 Core System..."
bash "${SCRIPT_DIR}/build_ros2.sh"

echo ""
echo "##########################################################"
echo "  All ROS 2 Components Built and Installed Successfully!"
echo "  Install Directory: ${WS_DIR}/install"
echo "##########################################################"
