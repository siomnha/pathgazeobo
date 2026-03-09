#!/usr/bin/env bash
set -euo pipefail

# Iris + depth camera + octomap 一键启动
# 支持两种模式：
#   1) image_proc (默认): GZ depth image + camera_info -> depth_image_proc -> PointCloud2
#   2) points_direct: GZ PointCloudPacked -> ROS PointCloud2
#
# 可覆盖环境变量：
#   WORLD_PATH, WORLD_NAME, MODEL_NAME, LINK_NAME, SENSOR_NAME
#   PIPELINE_MODE, ROS_POINTS_TOPIC, OCTOMAP_FRAME, RESOLUTION, MAX_RANGE

WORLD_PATH="${WORLD_PATH:-/workspace/pathgazeobo/goaero_mission3_v1.sdf}"
WORLD_NAME="${WORLD_NAME:-goaero_mission3}"
MODEL_NAME="${MODEL_NAME:-sitl_iris}"
LINK_NAME="${LINK_NAME:-base_link}"
SENSOR_NAME="${SENSOR_NAME:-front_depth}"
PIPELINE_MODE="${PIPELINE_MODE:-image_proc}" # image_proc | points_direct

ROS_POINTS_TOPIC="${ROS_POINTS_TOPIC:-/depth/points}"
OCTOMAP_FRAME="${OCTOMAP_FRAME:-map}"
RESOLUTION="${RESOLUTION:-0.15}"
MAX_RANGE="${MAX_RANGE:-20.0}"

BASE_GZ_TOPIC="/world/${WORLD_NAME}/model/${MODEL_NAME}/link/${LINK_NAME}/sensor/${SENSOR_NAME}"
GZ_IMAGE_TOPIC="${BASE_GZ_TOPIC}/image"
GZ_INFO_TOPIC="${BASE_GZ_TOPIC}/camera_info"
GZ_POINTS_TOPIC="${BASE_GZ_TOPIC}/points"

PIDS=()

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] 缺少命令: $1"
    exit 1
  fi
}

start_bg() {
  "$@" &
  PIDS+=("$!")
}

cleanup() {
  echo "[INFO] 停止后台进程..."
  for (( idx=${#PIDS[@]}-1 ; idx>=0 ; idx-- )); do
    kill "${PIDS[idx]}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

need_cmd gz
need_cmd ros2

cat <<ENVINFO
[INFO] 推荐在所有终端统一以下环境变量（否则常见“有 topic 但无消息”）：
  export ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}
  export ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY:-0}
  export GZ_PARTITION=${GZ_PARTITION:-default}
ENVINFO

echo "[1/5] 启动 Gazebo: ${WORLD_PATH}"
start_bg gz sim -r "${WORLD_PATH}"
sleep 5

echo "[2/5] 检查 Gazebo 侧 depth 话题"
gz topic -l | rg -E "${SENSOR_NAME}|camera_info|points" || true

if [[ "${PIPELINE_MODE}" == "image_proc" ]]; then
  echo "[3/5] 启动 ros_gz_bridge (image + camera_info)"
  start_bg ros2 run ros_gz_bridge parameter_bridge \
    "${GZ_IMAGE_TOPIC}@sensor_msgs/msg/Image@gz.msgs.Image" \
    "${GZ_INFO_TOPIC}@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo"
  sleep 2

  echo "[4/5] 启动 depth_image_proc -> ${ROS_POINTS_TOPIC}"
  start_bg ros2 run depth_image_proc point_cloud_xyz_node \
    --ros-args \
    -r image_rect:="${GZ_IMAGE_TOPIC}" \
    -r camera_info:="${GZ_INFO_TOPIC}" \
    -r points:="${ROS_POINTS_TOPIC}"
  sleep 2
elif [[ "${PIPELINE_MODE}" == "points_direct" ]]; then
  echo "[3/5] 启动 ros_gz_bridge (PointCloudPacked 直桥)"
  start_bg ros2 run ros_gz_bridge parameter_bridge \
    "${GZ_POINTS_TOPIC}@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked"
  sleep 2

  echo "[4/5] 跳过 depth_image_proc（使用直桥点云）"
  ROS_POINTS_TOPIC="${GZ_POINTS_TOPIC}"
else
  echo "[ERROR] 不支持的 PIPELINE_MODE=${PIPELINE_MODE}，可选: image_proc | points_direct"
  exit 1
fi

echo "[5/5] 启动 octomap_server，订阅: ${ROS_POINTS_TOPIC}"
start_bg ros2 run octomap_server octomap_server_node \
  --ros-args \
  -p resolution:="${RESOLUTION}" \
  -p frame_id:="${OCTOMAP_FRAME}" \
  -p sensor_model/max_range:="${MAX_RANGE}" \
  -r cloud_in:="${ROS_POINTS_TOPIC}"

cat <<CHECKS
[INFO] 现在请在另一个终端依次验证：
  ros2 topic info ${ROS_POINTS_TOPIC} -v
  ros2 topic echo ${ROS_POINTS_TOPIC} --once
  ros2 topic hz ${ROS_POINTS_TOPIC}
  ros2 topic echo /octomap_full --once
CHECKS

wait
