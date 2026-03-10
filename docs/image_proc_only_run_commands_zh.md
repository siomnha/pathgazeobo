# Image Proc 链路最小运行指南（只保留 depth image -> point cloud -> octomap）

> 目标：只走 `depth_image_proc` 路线，不走 `PointCloudPacked` 直桥。

## 1) 需要改的文件

### A. 你 **SITL 仓库**里的 Iris 模型（必须改）
文件（实际生效二选一）：
- `<ardupilot_gazebo>/models/iris/model.sdf`
- `<ardupilot_gazebo>/models/iris_with_standoffs/model.sdf`

在 `base_link` 下确保有如下深度相机（重点是 `<camera><image><clip>` 结构）：

```xml
<sensor name="front_depth" type="depth_camera">
  <pose>0.12 0 0.03 0 0 0</pose>
  <always_on>1</always_on>
  <update_rate>15</update_rate>
  <topic>/front_depth</topic>
  <visualize>true</visualize>
  <camera>
    <horizontal_fov>1.047</horizontal_fov>
    <image>
      <width>640</width>
      <height>480</height>
      <format>R_FLOAT32</format>
    </image>
    <clip>
      <near>0.15</near>
      <far>20.0</far>
    </clip>
  </camera>
</sensor>
```

> 如果你已经在本仓库用过补丁脚本，可再次执行（会重写为标准结构）：
>
> `MODEL_SDF=/abs/path/to/your/iris/model.sdf ./scripts/patch_sitl_iris_depth_camera.sh`

### B. 本仓库世界文件（建议确认）
文件：`goaero_mission3_v1.sdf`

确认 world include 的机体是 SITL 用的模型（例如 `model://iris`，`name` 为 `sitl_iris`）。

---

## 2) 运行命令（5 个终端）

以下命令默认你已经能启动 Gazebo Harmonic 和 SITL。

### 终端 1：Gazebo
```bash
gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

### 终端 2：SITL + MAVProxy
```bash
cd /path/to/ardupilot
sim_vehicle.py -v ArduCopter -f gazebo-iris --console --map
```

### 终端 3：桥接 image + camera_info（只用 image_proc 链路）
```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  /front_depth@sensor_msgs/msg/Image@gz.msgs.Image \
  /camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

> 如果你的 Gazebo 话题是 world scoped（例如 `/world/.../sensor/front_depth/image`），
> 就把上面 `/front_depth` 和 `/camera_info` 替换成对应长话题名。

> 如果你的 Gazebo 话题是 world scoped（例如 `/world/.../sensor/front_depth/image`），
> 就把上面 `/front_depth` 和 `/camera_info` 替换成对应长话题名。


### 终端 4：depth_image_proc 生成点云
```bash
source /opt/ros/humble/setup.bash
ros2 run depth_image_proc point_cloud_xyz_node --ros-args \
  -r image_rect:=/front_depth \
  -r camera_info:=/camera_info \
  -r points:=/depth/points
```

### 终端 5：octomap_server
```bash
source /opt/ros/humble/setup.bash
ros2 run octomap_server octomap_server_node --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

---

## 3) 验证命令（按顺序）

```bash
# Gazebo 侧确认有图像
gz topic -e --topic /front_depth

# ROS 侧确认 image 过桥成功
ros2 topic echo /front_depth --once

# depth_image_proc 输出点云
ros2 topic echo /depth/points --once
ros2 topic hz /depth/points

# OctoMap 输出
ros2 topic echo /octomap_full --once
```

---

## 4) 一条原则（避免再次跑偏）

如果你选择了 image proc 链路：
- 只看 `/front_depth` + `/camera_info` + `/depth/points`
- 不要再用 `/front_depth/points` 直桥命令

---

## 5) 一键脚本（自动识别短话题/长话题）

本仓库脚本支持自动识别 `flat`（`/front_depth`）和 `world_scoped`（`/world/.../image`）两种布局：

```bash
PIPELINE_MODE=image_proc TOPIC_LAYOUT=auto ./scripts/run_iris_octomap_pipeline.sh
```

---

## 6) 你这次遇到的核心问题：UAV TF 缺失与建图“拖影”

如果 `/octomap_full` 有数据，但地图像“相机固定在机头前方”或者飞行时出现明显拖影，通常是 TF 问题：

1. 缺少 `map -> base_link`（机体位姿）动态 TF；
2. 缺少 `base_link -> front_depth`（相机外参）TF；
3. `octomap_server` 的 `frame_id` 设成了不稳定或不连通的坐标系。

### 推荐做法（先稳定，再进阶）

#### A. 先用机体系稳定建图（最快验证）

把 octomap 固定到机体坐标系，先确认没有“固定在前方”的错觉：

```bash
ros2 run octomap_server octomap_server_node --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=base_link \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

#### B. 补上相机外参 TF（base_link -> front_depth）

相机参数与 SDF `pose` 对齐（默认 `0.12 0 0.03 0 0 0`）：

```bash
ros2 run tf2_ros static_transform_publisher \
  0.12 0 0.03 0 0 0 base_link front_depth
```

#### C. 最终切回全局地图（map）

当你确认 SITL/定位链路已提供连续 `map -> base_link` 后，再把 `octomap_server` 改回：

```bash
-p frame_id:=map
```

### 快速检查 TF 是否完整

```bash
ros2 run tf2_tools view_frames
ros2 topic echo /tf --once
ros2 topic echo /tf_static --once
```

