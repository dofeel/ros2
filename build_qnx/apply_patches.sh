#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/qnx_patches"

echo "=== Applying QNX patches to ROS 2 workspace ==="

apply_patch() {
    local repo_path="$1"
    local patch_file="$2"
    if [ -d "${WS_DIR}/${repo_path}" ] && [ -f "${patch_file}" ]; then
        echo "Applying $(basename "${patch_file}") -> ${repo_path}..."
        git -C "${WS_DIR}/${repo_path}" apply "${patch_file}" 2>/dev/null || {
            echo "  (Already applied or skipped)"
        }
    fi
}

apply_patch "src/eProsima/Fast-DDS" "${PATCHES_DIR}/01_fastdds_qnx.patch"
apply_patch "src/eProsima/Fast-CDR" "${PATCHES_DIR}/02_fastcdr_qnx.patch"
apply_patch "src/ros2/rcutils" "${PATCHES_DIR}/03_rcutils_qnx.patch"
apply_patch "src/ros2/rcl" "${PATCHES_DIR}/04_rcl_qnx.patch"
apply_patch "src/ros2/rclcpp" "${PATCHES_DIR}/05_rclcpp_qnx.patch"
apply_patch "src/ros2/ros2_tracing" "${PATCHES_DIR}/06_ros2_tracing_qnx.patch"
apply_patch "src/ros2/yaml_cpp_vendor" "${PATCHES_DIR}/07_yaml_cpp_vendor_qnx.patch"
apply_patch "src/yaml-cpp" "${PATCHES_DIR}/08_yaml_cpp_qnx.patch"

# Extra package.xml files and ignores
echo "Installing supplementary package.xml files..."
if [ -d "${WS_DIR}/src/eigen" ] && [ -f "${PATCHES_DIR}/extra_files/eigen_package.xml" ]; then
    cp -f "${PATCHES_DIR}/extra_files/eigen_package.xml" "${WS_DIR}/src/eigen/package.xml"
fi
if [ -d "${WS_DIR}/src/libyaml" ] && [ -f "${PATCHES_DIR}/extra_files/libyaml_package.xml" ]; then
    cp -f "${PATCHES_DIR}/extra_files/libyaml_package.xml" "${WS_DIR}/src/libyaml/package.xml"
fi
if [ -d "${WS_DIR}/src/yaml-cpp" ] && [ -f "${PATCHES_DIR}/extra_files/yaml_cpp_package.xml" ]; then
    cp -f "${PATCHES_DIR}/extra_files/yaml_cpp_package.xml" "${WS_DIR}/src/yaml-cpp/package.xml"
fi
if [ -d "${WS_DIR}/src/ament/ament_package/ament_package/template/prefix_level" ] && [ -f "${SCRIPT_DIR}/qnx_setup.sh.in" ]; then
    cp -f "${SCRIPT_DIR}/qnx_setup.sh.in" "${WS_DIR}/src/ament/ament_package/ament_package/template/prefix_level/qnx_setup.sh.in"
fi
if [ -d "${WS_DIR}/src/eProsima/googletest" ]; then
    touch "${WS_DIR}/src/eProsima/googletest/COLCON_IGNORE"
fi
if [ -d "${WS_DIR}/src/yaml-cpp/test" ]; then
    touch "${WS_DIR}/src/yaml-cpp/test/COLCON_IGNORE"
fi
if [ -d "${WS_DIR}/src/orocos_kinematics_dynamics/python_orocos_kdl" ]; then
    touch "${WS_DIR}/src/orocos_kinematics_dynamics/python_orocos_kdl/COLCON_IGNORE"
fi

echo "=== All QNX patches and configurations applied successfully! ==="
