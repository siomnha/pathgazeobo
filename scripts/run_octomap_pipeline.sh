#!/usr/bin/env bash
set -euo pipefail

# 这是一个最小化示例脚本：
# 1) 启动 Gazebo 世界
# 2) 桥接深度图与相机内参
# 3) 深度图转点云
# 4) 启动 octomap_server
#
# 注意：你必须根据实际模型名 / link 名 / sensor 名修改下面的话题。

WORLD_PATH="/workspace/pathgazeobo/goaero_mission3_v1.sdf"
GZ_IMAGE_TOPIC="/world/goaero_mission3/model/depth_rig/link/base_link/sensor/front_depth/image"
GZ_INFO_TOPIC="/world/goaero_mission3/model/depth_rig/link/base_link/sensor/front_depth/camera_info"
ROS_IMAGE_TOPIC="$GZ_IMAGE_TOPIC"
ROS_INFO_TOPIC="$GZ_INFO_TOPIC"
ROS_POINTS_TOPIC="/depth/points"

if ! command -v gz >/dev/null 2>&1; then
  echo "[ERROR] gz 未安装或不在 PATH。"
  exit 1
fi

if ! command -v ros2 >/dev/null 2>&1; then
  echo "[ERROR] ros2 未安装或不在 PATH。"
  exit 1
fi

echo "[1/4] 启动 Gazebo..."
gz sim -r "$WORLD_PATH" &
PID_GZ=$!
sleep 2

echo "[2/4] 启动 ros_gz_bridge..."
ros2 run ros_gz_bridge parameter_bridge \
  "${GZ_IMAGE_TOPIC}@sensor_msgs/msg/Image@gz.msgs.Image" \
  "${GZ_INFO_TOPIC}@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo" &
PID_BRIDGE=$!
sleep 2

echo "[3/4] 启动 depth_image_proc..."
ros2 run depth_image_proc point_cloud_xyz_node \
  --ros-args \
  -r image_rect:="$ROS_IMAGE_TOPIC" \
  -r camera_info:="$ROS_INFO_TOPIC" \
  -r points:="$ROS_POINTS_TOPIC" &
PID_PC=$!
sleep 2

echo "[4/4] 启动 octomap_server..."
ros2 run octomap_server octomap_server_node \
  --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=15.0 \
  -r cloud_in:="$ROS_POINTS_TOPIC" &
PID_OCTO=$!

cleanup() {
  echo "[INFO] 停止所有后台进程..."
  kill "$PID_OCTO" "$PID_PC" "$PID_BRIDGE" "$PID_GZ" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[INFO] 管线已启动。按 Ctrl+C 退出。"
wait "$PID_OCTO"
