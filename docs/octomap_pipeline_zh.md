# ArduPilot SITL + Gazebo 深度相机到 OctoMap（中文实战）


## 0) 先给你“能直接复制”的命令（目标：稳定拿到 `/octomap_full`）

> 你现场遇到的核心症状是：**Gazebo 有 depth topic，但 ROS `echo/hz` 没消息**。先按下面固定顺序跑，避免混用两条链路。

### 0.1 终端 A：统一环境 + 启动 Gazebo

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export ROS_LOCALHOST_ONLY=0
export GZ_PARTITION=default

gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

### 0.2 终端 B：推荐链路（image + camera_info -> depth_image_proc）

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export ROS_LOCALHOST_ONLY=0
export GZ_PARTITION=default

# 先确认真实 GZ 话题名（不要手猜）
gz topic -l | rg 'front_depth|camera_info|image|points'

# 把下面两条替换成你上一步看到的“完整路径”
GZ_IMAGE=/world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/image
GZ_INFO=/world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/camera_info

ros2 run ros_gz_bridge parameter_bridge   ${GZ_IMAGE}@sensor_msgs/msg/Image@gz.msgs.Image   ${GZ_INFO}@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

### 0.3 终端 C：depth_image_proc 出点云

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export ROS_LOCALHOST_ONLY=0

GZ_IMAGE=/world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/image
GZ_INFO=/world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/camera_info

ros2 run depth_image_proc point_cloud_xyz_node   --ros-args   -r image_rect:=${GZ_IMAGE}   -r camera_info:=${GZ_INFO}   -r points:=/depth/points
```

### 0.4 终端 D：启动 OctoMap

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0

ros2 run octomap_server octomap_server_node   --ros-args   -p frame_id:=map   -p resolution:=0.15   -p sensor_model/max_range:=20.0   -r cloud_in:=/depth/points
```

### 0.5 终端 E：只做验证

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0

ros2 topic info /depth/points -v
ros2 topic echo /depth/points --once
ros2 topic hz /depth/points
ros2 topic echo /octomap_full --once
```

### 0.6 如果你坚持“points 直桥”而不是 image_proc

可以，但建议只在 image 链路稳定后再试。命令（同样要用完整路径）：

```bash
ros2 run ros_gz_bridge parameter_bridge   /world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/points@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked
```

若 `ros2 topic hz` 仍为 0，优先回到 image_proc 路线定位，因为它更容易观察每一级数据。

### 0.7 “有 topic 但无消息”最常见 5 个原因

1. **桥接了错误 topic 名**（只桥了 `/front_depth`，实际在 `/world/.../front_depth/...`）。
2. **终端环境变量不一致**（`ROS_DOMAIN_ID`、`ROS_LOCALHOST_ONLY`、`GZ_PARTITION`）。
3. **链路混用**（一会儿看 `/front_depth/points`，一会儿 octomap 订阅 `/depth/points`）。
4. **Gazebo 传感器未持续发布**（先 `gz topic -e -n 1 <topic>` 确认确实有数据包）。
5. **TF/固定坐标缺失**（点云有了但 octomap 没输出，可先补 `map -> base_link` 静态 TF）。

---

这份文档按你当前诉求重排：**先给“iris 这类无人机模型 + 深度相机 + OctoMap”的完整管线**，再给“没有无人机模型时的过渡方案”。

---

## 1) 首选方案：先搭一个可飞的 Iris + Depth Camera（最可行）

你问得很对：如果最终目标是路径规划联调，**最可行**就是尽快用现成 copter（例如 iris）把在线建图链路跑通。仓库里已补充一个可直接使用的 `models/iris_with_depth/model.sdf`。

### 1.1 模型来源建议

常见来源：

- ArduPilot / Gazebo 生态已有 iris 模型（含电机、IMU、控制接口）。
- 你 SITL 仓库若已带 `iris` 或近似模型，优先复用，避免从零搭飞行器动力学。
- 若你当前仓库没有现成模型，可先用 `models/iris_with_depth/model.sdf`（已含 `front_depth`）。

### 1.2 在 iris 机体 link 上加 depth_camera

把下面传感器片段加到机体主 link（常见是 `base_link`）：

```xml
<sensor name="front_depth" type="depth_camera">
  <pose>0.12 0 0.02 0 0 0</pose>
  <update_rate>15</update_rate>
  <always_on>1</always_on>
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

> 说明：
>
> - 若你后续算力紧张，先改到 `320x240@10Hz`。
> - Gazebo 实际 topic 往往带上完整路径，需用 `gz topic -l` 确认。

### 1.3 Iris + OctoMap 在线管线（推荐启动顺序）

A. 启动 Gazebo（加载你的 world + iris 模型）

```bash
gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

B. 启动 ArduPilot SITL（沿用你现有仓库步骤）

C. 桥接深度图和内参（示例话题，按实际路径替换）

```bash
ros2 run ros_gz_bridge parameter_bridge \
  /world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/image@sensor_msgs/msg/Image@gz.msgs.Image \
  /world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

D. 深度图转点云

```bash
ros2 run depth_image_proc point_cloud_xyz_node \
  --ros-args \
  -r image_rect:=/world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/image \
  -r camera_info:=/world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/camera_info \
  -r points:=/depth/points
```

E. 点云融合为 OctoMap

```bash
ros2 run octomap_server octomap_server_node \
  --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

F. 必要时补最小 TF（仅调试）

```bash
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map base_link
```

---

## 2) 你没有无人机模型时（过渡方案）

如果你当前真的没有可用 copter，可先用 `depth_rig` 作为传感器载体验证建图链路，再迁移到 iris。

### 2.1 `depth_rig` 示例模型（放 world 内）

```xml
<model name="depth_rig">
  <static>false</static>
  <pose>0 0 1.5 0 0 0</pose>
  <link name="base_link">
    <inertial>
      <mass>1.0</mass>
      <inertia>
        <ixx>0.01</ixx><iyy>0.01</iyy><izz>0.01</izz>
        <ixy>0</ixy><ixz>0</ixz><iyz>0</iyz>
      </inertia>
    </inertial>
    <collision name="body_col">
      <geometry><box><size>0.2 0.2 0.1</size></box></geometry>
    </collision>
    <visual name="body_vis">
      <geometry><box><size>0.2 0.2 0.1</size></box></geometry>
    </visual>
    <sensor name="front_depth" type="depth_camera">
      <pose>0.12 0 0 0 0 0</pose>
      <update_rate>20</update_rate>
      <always_on>1</always_on>
      <topic>/depth_camera</topic>
      <camera>
        <horizontal_fov>1.047</horizontal_fov>
        <image>
          <width>640</width>
          <height>480</height>
          <format>R_FLOAT32</format>
        </image>
        <clip>
          <near>0.15</near>
          <far>15.0</far>
        </clip>
      </camera>
    </sensor>
  </link>
</model>
```

---

## 3) 你问的关键问题：能不能直接把 SDF world 变成 OctoMap，跳过 octomap_server？

短答案：**没有通用的一步到位默认方案**。

可选路线：

1. **标准在线路线（推荐）**：Depth → PointCloud2 → `octomap_server`。
2. **离线几何转换**：直接解析 SDF 几何生成 `.bt/.ot`（需自写工具或转换程序）。
3. **Gazebo occupancy 插件**：得到 occupancy 数据后再转 OctoMap（通常仍要额外转换）。

如果你的规划器“只吃 `octomap_msgs/Octomap`”，最稳仍是第 1 条或自己实现 world→octomap 转换器。

---

## 4) 快速验证清单

1. `gz topic -l | rg -E 'depth|camera_info'`
2. `ros2 topic list | rg -E 'front_depth|depth'`
3. `ros2 topic echo /depth/points --once`
4. `ros2 topic echo /octomap_full --once`

---

## 5) 接 3D 规划器的接口建议

- 输入统一：`/octomap_full`（`octomap_msgs/Octomap`）
- 规划坐标系：`map`
- 状态估计与目标点都放在 `map`

建议先录包做离线重放：

```bash
ros2 bag record /octomap_full /tf /tf_static
```
