# 改哪里、怎么改：SITL Iris + Depth Camera 最小改动指南

这份文档只回答两件事：

1. **你到底要改哪个文件**
2. **每一步具体怎么改、怎么验证**

---

## 0. 先记住核心原则

你要改的是 **SITL 实际加载的 Iris 模型 SDF**，不是随便一个本地占位模型。

- ✅ 目标文件（常见）：
  - `<ardupilot_gazebo>/models/iris/model.sdf`
  - 或 `<ardupilot_gazebo>/models/iris_with_standoffs/model.sdf`
- ❌ 非目标（仅本地演示）：
  - `/workspace/pathgazeobo/models/iris_with_depth/model.sdf`

---

## 1. 改 world：确保加载的是 SITL iris

文件：`/workspace/pathgazeobo/goaero_mission3_v1.sdf`

你应看到（或改成）下面这种 include：

```xml
<include>
  <uri>model://iris</uri>
  <name>sitl_iris</name>
  <pose>0 0 0.2 0 0 0</pose>
</include>
```

> 含义：世界里默认机体名为 `sitl_iris`，后续 bridge 话题就按这个 model 名拼。

---

## 2. 改 SITL 模型：加 depth sensor

### 方案 A（推荐）自动补丁

```bash
cd /workspace/pathgazeobo
./scripts/patch_sitl_iris_depth_camera.sh <你的 ardupilot_gazebo 路径>
```

或直接指定模型文件：

```bash
MODEL_SDF=/abs/path/to/iris/model.sdf ./scripts/patch_sitl_iris_depth_camera.sh
```

脚本会自动：

- 注入（或重写）`front_depth` 为标准 Gazebo depth_camera 结构
- 写入备份 `model.sdf.bak`
- 若已存在旧/错误 `front_depth`，会先移除再写入标准版本

### 方案 B 手工改（如果你不想跑脚本）

在 SITL iris 的 `base_link` 下加入：

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

## 3. 环境变量：防止加载错 iris 模型

启动前建议每个终端设置：

```bash
source /opt/ros/humble/setup.bash
export GZ_SIM_RESOURCE_PATH=<你的 ardupilot_gazebo 路径>/models:$GZ_SIM_RESOURCE_PATH
```

> 作用：优先找到你 SITL 仓库里的 `model://iris`，避免误加载其他来源同名模型。

---

## 4. 重启顺序（改完模型后必须）

1. 关掉旧 `gz sim`。
2. 关掉旧 `sim_vehicle.py`。
3. 重启 Gazebo world。
4. 重启 SITL。

不重启的话，SDF 变更不会生效。

---

## 5. 怎么确认“改对了”

### 5.1 文件级确认（静态）

在你真正修改的 SITL `model.sdf` 里查：

```bash
rg -n "front_depth|depth_camera|horizontal_fov|R_FLOAT32|<near>|<far>" /abs/path/to/iris/model.sdf
```

### 5.2 运行级确认（动态）

```bash
gz topic -l | rg -E "front_depth|camera_info"
```

应该至少有：

- `.../sensor/front_depth/image`
- `.../sensor/front_depth/camera_info`

### 5.3 ROS 侧确认

```bash
ros2 topic list | rg front_depth
```

---

## 6. 如果还是不出图像

按这个顺序排查：

1. 确认改的是 SITL 正在加载的那个 `model.sdf`。
2. 确认已完整重启 `gz sim` + SITL。
3. 确认 `GZ_SIM_RESOURCE_PATH` 指向 SITL models。
4. 用 `gz topic -l` 看真实 model 名是否 `sitl_iris`（若不是，bridge 话题需改）。

---

## 7. 你只要改这 3 类文件

- `goaero_mission3_v1.sdf`（世界里 include 哪个机体）
- SITL 仓库中的 `iris*/model.sdf`（depth sensor 本体）
- 你的 bridge/脚本中的话题路径（匹配真实 model 名）

其他文件都可以先不动。
