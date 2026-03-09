#!/usr/bin/env bash
set -euo pipefail

# Iris + depth camera + octomap 的最小启动脚本
# 你可以通过环境变量覆盖默认值：
#   WORLD_PATH, WORLD_NAME, MODEL_NAME, LINK_NAME, SENSOR_NAME, RESOLUTION, MAX_RANGE

WORLD_PATH="${WORLD_PATH:-/workspace/pathgazeobo/goaero_mission3_v1.sdf}"
WORLD_NAME="${WORLD_NAME:-goaero_mission3}"
MODEL_NAME="${MODEL_NAME:-sitl_iris}"
LINK_NAME="${LINK_NAME:-base_link}"
SENSOR_NAME="${SENSOR_NAME:-front_depth}"
RESOLUTION="${RESOLUTION:-0.15}"
MAX_RANGE="${MAX_RANGE:-20.0}"

BASE_GZ_TOPIC="/world/${WORLD_NAME}/model/${MODEL_NAME}/link/${LINK_NAME}/sensor/${SENSOR_NAME}"
GZ_IMAGE_TOPIC="${BASE_GZ_TOPIC}/image"
GZ_INFO_TOPIC="${BASE_GZ_TOPIC}/camera_info"
ROS_POINTS_TOPIC="/depth/points"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] 缺少命令: $1"
    exit 1
  fi
}

need_cmd gz
need_cmd ros2

echo "[1/4] 启动 Gazebo: ${WORLD_PATH}"
gz sim -r "${WORLD_PATH}" &
PID_GZ=$!
sleep 3

echo "[2/4] 启动 ros_gz_bridge"
ros2 run ros_gz_bridge parameter_bridge \
  "${GZ_IMAGE_TOPIC}@sensor_msgs/msg/Image@gz.msgs.Image" \
  "${GZ_INFO_TOPIC}@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo" &
PID_BRIDGE=$!
sleep 2

echo "[3/4] 启动 depth_image_proc"
ros2 run depth_image_proc point_cloud_xyz_node \
  --ros-args \
  -r image_rect:="${GZ_IMAGE_TOPIC}" \
  -r camera_info:="${GZ_INFO_TOPIC}" \
  -r points:="${ROS_POINTS_TOPIC}" &
PID_PC=$!
sleep 2

echo "[4/4] 启动 octomap_server"
ros2 run octomap_server octomap_server_node \
  --ros-args \
  -p resolution:="${RESOLUTION}" \
  -p frame_id:=map \
  -p sensor_model/max_range:="${MAX_RANGE}" \
  -r cloud_in:="${ROS_POINTS_TOPIC}" &
PID_OCTO=$!

cleanup() {
  echo "[INFO] 停止后台进程..."
  kill "$PID_OCTO" "$PID_PC" "$PID_BRIDGE" "$PID_GZ" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[INFO] 已启动。若看不到话题，请先执行: gz topic -l"
wait "$PID_OCTO"
