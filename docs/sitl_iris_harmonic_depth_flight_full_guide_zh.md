# 从 0 到 1：Gazebo Harmonic 生成 SITL Iris → 加 Depth Camera → 起飞建图（中文全流程）

这份文档按**正确执行顺序**组织，目标是让你完成三件事：

1. 在 Gazebo Harmonic 中运行 ArduPilot SITL 的 Iris。
2. 给 SITL Iris 模型添加 depth camera。
3. 起飞并在线生成 OctoMap（供规划器使用）。

---

## 目录（按执行顺序）

1. 前置条件检查
2. 启动 SITL Iris + Gazebo Harmonic
3. 给 SITL Iris 模型加 depth camera
4. 重启并验证 depth 话题
5. 启动 ROS 2 桥接、点云、OctoMap
6. 飞行控制（起飞 / 移动 / 降落）
7. 常见错误与修复

---

## 1) 前置条件检查

### 1.1 必备软件

- ArduPilot + 你的 SITL Gazebo 适配仓库（例如 ardupilot_gazebo）
- Gazebo Harmonic（`gz sim`）
- ROS 2（示例用 Humble）

安装 ROS 2 侧建图工具：

```bash
sudo apt update
sudo apt install -y \
  ros-humble-ros-gz-bridge \
  ros-humble-depth-image-proc \
  ros-humble-octomap-server \
  ros-humble-tf2-ros \
  ros-humble-rviz2
```

### 1.2 环境加载

每个终端都建议先执行：

```bash
source /opt/ros/humble/setup.bash
export GZ_SIM_RESOURCE_PATH=<你的 ardupilot_gazebo 路径>/models:$GZ_SIM_RESOURCE_PATH
```

---

## 1.5 先改 world include（避免加载本地占位机体）

请把 `goaero_mission3_v1.sdf` 里的本地占位模型：

- `file:///workspace/pathgazeobo/models/iris_with_depth`

改为 SITL 用的：

- `model://iris`（示例命名：`sitl_iris`）

这样 Gazebo 场景只会出现 SITL 机体，不会和本地占位机体混淆控制对象。

---

## 2) 先跑通 SITL Iris + Gazebo Harmonic（不改模型前）

> 先验证“飞控链路可用”，再加传感器，定位问题更快。

### 2.1 终端 A：启动 Gazebo 世界

```bash
gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

### 2.2 终端 B：启动 ArduPilot SITL（示例）

```bash
cd <你的 ardupilot 目录>
source /opt/ros/humble/setup.bash
sim_vehicle.py -v ArduCopter -f gazebo-iris --console --map
```

> 若你现在使用的 frame 不是 `gazebo-iris`，请换成你当前可用配置。

### 2.3 基础联通性检查

```bash
gz topic -l | rg -E 'imu|odometry|pose|iris'
```

如果这里就失败，先不要进入 depth camera 步骤。

### 2.4 MAVProxy 连不上时的关键排查（你现在这个问题）

如果 MAVProxy 提示一直 `waiting for heartbeat`，通常是下面两类原因：

1. **加载了错误的 iris 模型**（只有外观，没有 ArduPilot 插件）。
2. **SITL 与 Gazebo 插件没连上**（模型/资源路径不对）。

先做这 3 条：

```bash
# 1) 看 SITL 是否在输出 heartbeat/状态
sim_vehicle.py -v ArduCopter -f gazebo-iris --console --map

# 2) 单独连接 MAVProxy（若没自动起）
mavproxy.py --master=tcp:127.0.0.1:5760 --console --map

# 3) 检查 Gazebo 是否使用了 sitl_iris 模型名
gz topic -l | rg -E 'sitl_iris|iris'
```

另外要确保 Gazebo 找到的是你 **SITL 仓库里的模型**，不是 Fuel 的同名 `iris`：

```bash
export GZ_SIM_RESOURCE_PATH=<你的 ardupilot_gazebo 路径>/models:$GZ_SIM_RESOURCE_PATH
```

然后重启 `gz sim` + `sim_vehicle.py`。

---

## 3) 给 SITL Iris 模型添加 depth camera（关键步骤）

你前面问得很关键：`iris_with_depth` 占位模型没有完整 ArduPilot 控制链。  
要飞起来并建图，应改 **SITL 实际使用的 iris model.sdf**。

### 3.1 自动补丁方式（推荐）

本仓库已提供脚本：`scripts/patch_sitl_iris_depth_camera.sh`

```bash
cd /workspace/pathgazeobo
./scripts/patch_sitl_iris_depth_camera.sh <你的 ardupilot_gazebo 路径>
```

或直接指定模型文件：

```bash
cd /workspace/pathgazeobo
MODEL_SDF=/abs/path/to/iris/model.sdf ./scripts/patch_sitl_iris_depth_camera.sh
```

脚本行为：

- 在 `base_link`（找不到则首个 link）注入 `front_depth`。
- 自动写入备份：`model.sdf.bak`。
- 若已存在同名传感器会跳过。

### 3.2 手工补丁方式（备选）

在 SITL iris 的 `base_link` 内加入：

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

---

## 4) 重启仿真并验证 depth 话题

> 模型改完后，需重启 Gazebo 和 SITL，确保新 SDF 生效。

### 4.1 重启顺序

1. 停掉旧的 `gz sim` 与 SITL。
2. 重新执行第 2.1 和第 2.2。

### 4.2 depth 话题检查

```bash
gz topic -l | rg -E 'front_depth|camera_info|depth'
```

你应看到类似：

- `/world/<world>/model/<iris_model>/link/base_link/sensor/front_depth/image`
- `/world/<world>/model/<iris_model>/link/base_link/sensor/front_depth/camera_info`

把真实话题名记下来，下一步会用到。

---

## 5) 启动 ROS 2 建图链路（Bridge → PointCloud → OctoMap）

下面假设真实路径为：

- `.../sensor/front_depth/image`
- `.../sensor/front_depth/camera_info`

### 5.1 终端 C：桥接图像与内参

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  /world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/image@sensor_msgs/msg/Image@gz.msgs.Image \
  /world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

### 5.2 终端 D：深度图转点云

```bash
source /opt/ros/humble/setup.bash
ros2 run depth_image_proc point_cloud_xyz_node \
  --ros-args \
  -r image_rect:=/world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/image \
  -r camera_info:=/world/goaero_mission3/model/sitl_iris/link/base_link/sensor/front_depth/camera_info \
  -r points:=/depth/points
```

### 5.3 终端 E：OctoMap 融合

```bash
source /opt/ros/humble/setup.bash
ros2 run octomap_server octomap_server_node \
  --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

### 5.4 数据检查

```bash
ros2 topic echo /depth/points --once
ros2 topic list | rg octomap
ros2 topic echo /octomap_full --once
```

如报 TF 问题，临时调试可用：

```bash
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map base_link
```

---

## 6) 飞行控制步骤（在建图链路已启动后）

### 6.1 MAVProxy 最小起飞

在 SITL 控制台 / MAVProxy：

```text
mode guided
arm throttle
takeoff 5
```

### 6.2 飞行采图建议

- 第一轮：直线前飞 5~10m → 悬停。
- 第二轮：方形轨迹（低速）扫图。
- 速度尽量慢，减少深度噪声与地图拖影。

### 6.3 降落结束

```text
mode land
```

落地后可 `disarm`，并停止桥接、点云和 OctoMap 节点。

---

## 7) 常见错误与修复

### 7.1 飞得起来但没有深度话题

- 模型未重载（忘记重启 gz sim）
- depth sensor 加错 link 或 XML 位置
- 补丁打到了错误模型文件

### 7.2 有 depth image 但没点云

- `camera_info` 未桥接成功
- `depth_image_proc` remap 与真实话题不一致

### 7.3 有点云但 OctoMap 空

- `frame_id` 与 TF 树不一致
- 时间戳不同步导致 TF 查询失败

### 7.4 CPU 太高

- 相机降为 `320x240@10Hz`
- `octomap_server` 分辨率改为 `0.2~0.3`

---

## 附：推荐你实际执行的最短路径

1. 跑通第 2 章 SITL 基线。  
2. 用第 3.1 脚本给 SITL iris 打 depth 补丁。  
3. 重启后做第 4 章话题验证。  
4. 起第 5 章建图管线。  
5. 按第 6 章起飞扫图。  

这样最稳，且最贴近你最终“飞行中在线 OctoMap + 路径规划”的目标。
