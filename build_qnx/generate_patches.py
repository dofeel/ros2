import os, subprocess, shutil

ws = '/home/user/ros2_ws'
patches_dir = os.path.join(ws, 'build_qnx', 'qnx_patches')
os.makedirs(patches_dir, exist_ok=True)
extra_files_dir = os.path.join(patches_dir, 'extra_files')
os.makedirs(extra_files_dir, exist_ok=True)

# 1. Fast-DDS patches
diff_fastdds = subprocess.check_output(['git', '-C', f'{ws}/src/eProsima/Fast-DDS', 'diff', 'CMakeLists.txt', 'cmake/']).decode()
with open(os.path.join(patches_dir, '01_fastdds_qnx.patch'), 'w') as f:
    f.write(diff_fastdds)

# 2. Fast-CDR patch
diff_fastcdr = subprocess.check_output(['git', '-C', f'{ws}/src/eProsima/Fast-CDR', 'diff']).decode()
with open(os.path.join(patches_dir, '02_fastcdr_qnx.patch'), 'w') as f:
    f.write(diff_fastcdr)

# 3. Copy Fast-DDS thirdparty submodule patches
fastdds_sub_patches = f'{ws}/src/eProsima/Fast-DDS/build_qnx/qnx_patches'
if os.path.exists(fastdds_sub_patches):
    for fn in os.listdir(fastdds_sub_patches):
        src = os.path.join(fastdds_sub_patches, fn)
        dst = os.path.join(patches_dir, f'fastdds_submodule_{fn}')
        shutil.copy2(src, dst)

# 4. rcutils
diff_rcutils = subprocess.check_output(['git', '-C', f'{ws}/src/ros2/rcutils', 'diff']).decode()
with open(os.path.join(patches_dir, '03_rcutils_qnx.patch'), 'w') as f:
    f.write(diff_rcutils)

# 5. rcl
diff_rcl = subprocess.check_output(['git', '-C', f'{ws}/src/ros2/rcl', 'diff']).decode()
with open(os.path.join(patches_dir, '04_rcl_qnx.patch'), 'w') as f:
    f.write(diff_rcl)

# 6. rclcpp
diff_rclcpp = subprocess.check_output(['git', '-C', f'{ws}/src/ros2/rclcpp', 'diff']).decode()
with open(os.path.join(patches_dir, '05_rclcpp_qnx.patch'), 'w') as f:
    f.write(diff_rclcpp)

# 7. ros2_tracing
diff_tracing = subprocess.check_output(['git', '-C', f'{ws}/src/ros2/ros2_tracing', 'diff']).decode()
with open(os.path.join(patches_dir, '06_ros2_tracing_qnx.patch'), 'w') as f:
    f.write(diff_tracing)

# 8. yaml_cpp_vendor
diff_yaml_vendor = subprocess.check_output(['git', '-C', f'{ws}/src/ros2/yaml_cpp_vendor', 'diff']).decode()
with open(os.path.join(patches_dir, '07_yaml_cpp_vendor_qnx.patch'), 'w') as f:
    f.write(diff_yaml_vendor)

# 9. yaml-cpp
diff_yamlcpp = subprocess.check_output(['git', '-C', f'{ws}/src/yaml-cpp', 'diff']).decode()
with open(os.path.join(patches_dir, '08_yaml_cpp_qnx.patch'), 'w') as f:
    f.write(diff_yamlcpp)

# 10. Extra non-git / new files needed for colcon build
shutil.copy2(f'{ws}/src/eigen/package.xml', os.path.join(extra_files_dir, 'eigen_package.xml'))
shutil.copy2(f'{ws}/src/libyaml/package.xml', os.path.join(extra_files_dir, 'libyaml_package.xml'))
shutil.copy2(f'{ws}/src/yaml-cpp/package.xml', os.path.join(extra_files_dir, 'yaml_cpp_package.xml'))

print('Patches generated successfully!')
