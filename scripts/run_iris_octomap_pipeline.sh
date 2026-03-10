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
#   ENABLE_CAMERA_STATIC_TF, BASE_FRAME, CAMERA_FRAME
#   CAMERA_X, CAMERA_Y, CAMERA_Z, CAMERA_ROLL, CAMERA_PITCH, CAMERA_YAW

WORLD_PATH="${WORLD_PATH:-/workspace/pathgazeobo/goaero_mission3_v1.sdf}"
WORLD_NAME="${WORLD_NAME:-goaero_mission3}"
MODEL_NAME="${MODEL_NAME:-sitl_iris}"
LINK_NAME="${LINK_NAME:-base_link}"
SENSOR_NAME="${SENSOR_NAME:-front_depth}"
PIPELINE_MODE="${PIPELINE_MODE:-image_proc}" # image_proc | points_direct
TOPIC_LAYOUT="${TOPIC_LAYOUT:-auto}" # auto | world_scoped | flat

ROS_POINTS_TOPIC="${ROS_POINTS_TOPIC:-/depth/points}"
OCTOMAP_FRAME="${OCTOMAP_FRAME:-map}"
RESOLUTION="${RESOLUTION:-0.15}"
MAX_RANGE="${MAX_RANGE:-20.0}"
ENABLE_CAMERA_STATIC_TF="${ENABLE_CAMERA_STATIC_TF:-0}"
BASE_FRAME="${BASE_FRAME:-base_link}"
CAMERA_FRAME="${CAMERA_FRAME:-front_depth}"
CAMERA_X="${CAMERA_X:-0.12}"
CAMERA_Y="${CAMERA_Y:-0.0}"
CAMERA_Z="${CAMERA_Z:-0.03}"
CAMERA_ROLL="${CAMERA_ROLL:-0.0}"
CAMERA_PITCH="${CAMERA_PITCH:-0.0}"
CAMERA_YAW="${CAMERA_YAW:-0.0}"

BASE_GZ_TOPIC="/world/${WORLD_NAME}/model/${MODEL_NAME}/link/${LINK_NAME}/sensor/${SENSOR_NAME}"
GZ_IMAGE_TOPIC="${BASE_GZ_TOPIC}/image"
GZ_INFO_TOPIC="${BASE_GZ_TOPIC}/camera_info"
GZ_POINTS_TOPIC="${BASE_GZ_TOPIC}/points"
GZ_IMAGE_TOPIC_FLAT="/${SENSOR_NAME}"
GZ_INFO_TOPIC_FLAT="/camera_info"
GZ_POINTS_TOPIC_FLAT="/${SENSOR_NAME}/points"

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

if [[ "${ENABLE_CAMERA_STATIC_TF}" == "1" ]]; then
  need_cmd ros2
fi

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
TOPIC_LIST="$(gz topic -l || true)"
echo "$TOPIC_LIST" | rg -E "${SENSOR_NAME}|camera_info|points" || true

if [[ "${TOPIC_LAYOUT}" == "auto" ]]; then
  if echo "$TOPIC_LIST" | rg -q "^${GZ_IMAGE_TOPIC}$"; then
    TOPIC_LAYOUT="world_scoped"
  elif echo "$TOPIC_LIST" | rg -q "^${GZ_IMAGE_TOPIC_FLAT}$"; then
    TOPIC_LAYOUT="flat"
  else
    echo "[ERROR] 未找到可用的 image topic。"
    echo "        期望其一: ${GZ_IMAGE_TOPIC} 或 ${GZ_IMAGE_TOPIC_FLAT}"
    exit 1
  fi
fi

if [[ "${TOPIC_LAYOUT}" == "world_scoped" ]]; then
  USE_GZ_IMAGE_TOPIC="${GZ_IMAGE_TOPIC}"
  USE_GZ_INFO_TOPIC="${GZ_INFO_TOPIC}"
  USE_GZ_POINTS_TOPIC="${GZ_POINTS_TOPIC}"
elif [[ "${TOPIC_LAYOUT}" == "flat" ]]; then
  USE_GZ_IMAGE_TOPIC="${GZ_IMAGE_TOPIC_FLAT}"
  USE_GZ_INFO_TOPIC="${GZ_INFO_TOPIC_FLAT}"
  USE_GZ_POINTS_TOPIC="${GZ_POINTS_TOPIC_FLAT}"
else
  echo "[ERROR] 不支持的 TOPIC_LAYOUT=${TOPIC_LAYOUT}，可选: auto | world_scoped | flat"
  exit 1
fi

echo "[INFO] 使用话题布局: ${TOPIC_LAYOUT}"
echo "[INFO] image topic: ${USE_GZ_IMAGE_TOPIC}"
echo "[INFO] info topic : ${USE_GZ_INFO_TOPIC}"
echo "[INFO] points topic: ${USE_GZ_POINTS_TOPIC}"

if [[ "${ENABLE_CAMERA_STATIC_TF}" == "1" ]]; then
  echo "[INFO] 启动静态TF: ${BASE_FRAME} -> ${CAMERA_FRAME}"
  start_bg ros2 run tf2_ros static_transform_publisher \
    "${CAMERA_X}" "${CAMERA_Y}" "${CAMERA_Z}" \
    "${CAMERA_ROLL}" "${CAMERA_PITCH}" "${CAMERA_YAW}" \
    "${BASE_FRAME}" "${CAMERA_FRAME}"
  sleep 1
fi

if [[ "${PIPELINE_MODE}" == "image_proc" ]]; then
  echo "[3/5] 启动 ros_gz_bridge (image + camera_info)"
  start_bg ros2 run ros_gz_bridge parameter_bridge \
    "${USE_GZ_IMAGE_TOPIC}@sensor_msgs/msg/Image@gz.msgs.Image" \
    "${USE_GZ_INFO_TOPIC}@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo"
  sleep 2

  echo "[4/5] 启动 depth_image_proc -> ${ROS_POINTS_TOPIC}"
  start_bg ros2 run depth_image_proc point_cloud_xyz_node \
    --ros-args \
    -r image_rect:="${USE_GZ_IMAGE_TOPIC}" \
    -r camera_info:="${USE_GZ_INFO_TOPIC}" \
    -r points:="${ROS_POINTS_TOPIC}"
  sleep 2
elif [[ "${PIPELINE_MODE}" == "points_direct" ]]; then
  echo "[3/5] 启动 ros_gz_bridge (PointCloudPacked 直桥)"
  start_bg ros2 run ros_gz_bridge parameter_bridge \
    "${USE_GZ_POINTS_TOPIC}@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked"
  sleep 2

  echo "[4/5] 跳过 depth_image_proc（使用直桥点云）"
  ROS_POINTS_TOPIC="${USE_GZ_POINTS_TOPIC}"
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
  ros2 run tf2_tools view_frames
CHECKS

if [[ "${OCTOMAP_FRAME}" == "map" ]]; then
  echo "[WARN] 当前 OCTOMAP_FRAME=map，需要存在动态 TF: map -> ${BASE_FRAME}。"
  echo "       若你暂时没有机体位姿TF，可先使用 OCTOMAP_FRAME=${BASE_FRAME} 做局部稳定建图。"
fi

wait
