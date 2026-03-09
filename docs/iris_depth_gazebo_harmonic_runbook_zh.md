# Gazebo Harmonic：Iris + Depth Camera 运行详解（中文）

本文是**可执行 runbook**，目标是让你在 Gazebo Harmonic 中把 `iris_with_depth` 跑起来，并稳定产出 OctoMap 数据供路径规划使用。

> 适用前提：
>
> - 你当前仓库含有：`goaero_mission3_v1.sdf` 与 `models/iris_with_depth/model.sdf`。
> - 你已经安装 ROS 2（示例按 Humble）与 Gazebo Harmonic。

---

## 0. 快速结果预期

跑通后你应能看到：

1. Gazebo 中出现 `iris_with_depth`。
2. Gazebo depth 话题存在（`.../sensor/front_depth/image`）。
3. ROS 2 中有 `/depth/points`。
4. ROS 2 中有 `/octomap_full`。

---

## 1. 环境准备（Harmonic + ROS 2）

### 1.1 安装必要 ROS 2 包

```bash
sudo apt update
sudo apt install -y \
  ros-humble-ros-gz-bridge \
  ros-humble-depth-image-proc \
  ros-humble-octomap-server \
  ros-humble-tf2-ros \
  ros-humble-rviz2
```

### 1.2 进入仓库并 source

```bash
cd /workspace/pathgazeobo
source /opt/ros/humble/setup.bash
```

> 如果你使用的是其他 ROS 发行版，把 `humble` 替换为对应版本。

---

## 2. 确认模型与世界文件

### 2.1 关键文件

- 世界：`goaero_mission3_v1.sdf`
- 模型：`models/iris_with_depth/model.sdf`
- 模型配置：`models/iris_with_depth/model.config`

### 2.2 确认 world 已 include 模型

`goaero_mission3_v1.sdf` 中应有类似：

```xml
<include>
  <uri>file:///workspace/pathgazeobo/models/iris_with_depth</uri>
  <name>iris_with_depth</name>
  <pose>0 0 0.2 0 0 0</pose>
</include>
```

如果你修改了仓库路径，请同步更新 `file://` 绝对路径。

---

## 3. 在 Gazebo Harmonic 启动世界

```bash
gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

### 3.1 检查模型是否成功加载

```bash
gz topic -l | rg iris_with_depth
```

如果看不到相关话题，优先检查：

- world 里的 `<include>` 路径是否正确。
- `model.config` 与 `model.sdf` 文件名是否匹配。
- `gz sim` 启动日志是否提示 URI 加载失败。

---

## 4. 桥接 depth image 与 camera_info 到 ROS 2

新开终端：

```bash
cd /workspace/pathgazeobo
source /opt/ros/humble/setup.bash

ros2 run ros_gz_bridge parameter_bridge \
  /world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/image@sensor_msgs/msg/Image@gz.msgs.Image \
  /world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

### 4.1 桥接验证

```bash
ros2 topic list | rg front_depth
```

---

## 5. 深度图转点云（PointCloud2）

再开终端：

```bash
cd /workspace/pathgazeobo
source /opt/ros/humble/setup.bash

ros2 run depth_image_proc point_cloud_xyz_node \
  --ros-args \
  -r image_rect:=/world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/image \
  -r camera_info:=/world/goaero_mission3/model/iris_with_depth/link/base_link/sensor/front_depth/camera_info \
  -r points:=/depth/points
```

### 5.1 点云验证

```bash
ros2 topic echo /depth/points --once
```

---

## 6. 运行 OctoMap Server

再开终端：

```bash
cd /workspace/pathgazeobo
source /opt/ros/humble/setup.bash

ros2 run octomap_server octomap_server_node \
  --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

### 6.1 OctoMap 验证

```bash
ros2 topic list | rg octomap
ros2 topic echo /octomap_full --once
```

---

## 7. TF 处理（调试必看）

若 `octomap_server` 报 TF 相关错误，可临时先给一个静态 TF（仅用于链路联调）：

```bash
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map base_link
```

> 长期方案应使用真实位姿链路（SITL / 里程计 / 状态估计）。

---

## 8. 一键脚本方式（仓库已有）

你也可以直接用脚本：

```bash
cd /workspace/pathgazeobo
source /opt/ros/humble/setup.bash
./scripts/run_iris_octomap_pipeline.sh
```

如模型名/世界名不同，可覆盖环境变量：

```bash
WORLD_NAME=goaero_mission3 MODEL_NAME=iris_with_depth SENSOR_NAME=front_depth ./scripts/run_iris_octomap_pipeline.sh
```

---

## 9. 如何“飞起来”：ArduPilot SITL 控制步骤（推荐）

> 重要说明：
>
> - 当前仓库内的 `iris_with_depth` 是“建图联调模型”，默认不等价于完整 ArduPilot 飞行动力学。
> - 若你要真实测试“飞行中建图”，建议切换到你 SITL 仓库中的 ArduPilot Iris 模型，并把 `front_depth` 传感器并入该模型。

### 9.1 启动顺序（建议 4 个终端）

1. 终端 A：`gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf`
2. 终端 B：启动 ArduPilot SITL（在你的 ardupilot 仓库）
3. 终端 C：运行桥接 + 点云 + OctoMap（按本 runbook 第 4~6 节）
4. 终端 D：MAVProxy / 地面站发飞行指令

### 9.2 给 SITL 自带 Iris 模型加 depth camera（关键）

你说得对：当前仓库 `iris_with_depth` 没有完整 ArduPilot 动力学控制链。
**正确做法**是把深度相机加到你 SITL 仓库里的 iris model.sdf。

#### 方法 A（推荐）：用本仓库脚本自动打补丁

```bash
cd /workspace/pathgazeobo
./scripts/patch_sitl_iris_depth_camera.sh <你的 ardupilot_gazebo 路径>
```

如果你已经知道模型文件路径：

```bash
MODEL_SDF=/abs/path/to/iris/model.sdf ./scripts/patch_sitl_iris_depth_camera.sh
```

脚本会：

- 在 `base_link`（或首个 link）下添加 `front_depth` 传感器。
- 自动生成 `model.sdf.bak` 备份。
- 若已存在 `front_depth`，则安全跳过。

#### 方法 B：手工编辑 SITL iris 的 model.sdf

在 iris 的机体 link（通常 `base_link`）里加入：

```xml
<sensor name="front_depth" type="depth_camera">
  <pose>0.12 0 0.03 0 0 0</pose>
  <always_on>1</always_on>
  <update_rate>15</update_rate>
  <topic>/front_depth</topic>
<<<<<<< codex/add-copter-with-depth-camera-to-simulate-octomap-2ws319
  <visualize>true</visualize>
=======
>>>>>>> main
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

#### 修改后校验

```bash
gz topic -l | rg -E 'front_depth|camera_info'
```

### 9.3 SITL 常见启动示例（以 ArduCopter 为例）

```bash
cd <你的 ardupilot 目录>
source /opt/ros/humble/setup.bash
sim_vehicle.py -v ArduCopter -f gazebo-iris --console --map
```

> 若你的 SITL 文档使用了不同 frame（如 `gazebo-iris` 以外），以你已有流程为准。

### 9.4 MAVProxy 最小起飞流程

在 MAVProxy 控制台中：

```text
mode guided
arm throttle
takeoff 5
```

含义：切 `GUIDED`、解锁、起飞到 5m 高度。

### 9.5 基础移动指令（用于扫图）

你可以用地面站发局部目标点（或 Mission 航点）让无人机扫过障碍区。实操建议：

- 先做“慢速直线 + 悬停”验证 OctoMap。
- 再做“方形轨迹”提升覆盖率。
- 保持较低速度，减少运动模糊和地图拖影。

### 9.6 降落与结束

```text
mode land
```

待落地后可 `disarm`，再结束桥接与建图节点。

---

## 10. Gazebo Harmonic 常见问题排查

### 10.1 看不到 depth image

排查顺序：

1. `model.sdf` 是否真的包含 `type="depth_camera"`。
2. `gz topic -l | rg front_depth` 是否有完整话题。
3. 渲染后端是否正常（Harmonic 常见为 Ogre2 路径）。

### 10.2 有图像但无点云

通常是 `camera_info` 没桥接成功，或 `depth_image_proc` remap 名字不一致。

### 10.3 有点云但 OctoMap 为空

高概率是 TF 框架不通或 `frame_id` 不一致（例如 map/base_link 错配）。

### 10.4 CPU 过高

建议从这三项先降：

- 分辨率：`640x480 -> 320x240`
- 帧率：`15Hz -> 10Hz`
- `octomap_server` 分辨率：`0.15 -> 0.2~0.3`

---

## 11. 给路径规划联调用的最小建议

- 统一消费 `/octomap_full`（`octomap_msgs/Octomap`）。
- 统一全局坐标系到 `map`。
- 先录包后规划，便于分离“建图问题”与“规划问题”：

```bash
ros2 bag record /octomap_full /tf /tf_static
```

当这条链路稳定后，再切换到真实 ArduPilot iris 动力学模型会更顺畅。
