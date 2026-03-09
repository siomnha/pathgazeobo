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
