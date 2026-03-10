# Draft Pipeline (Fixed): Iris + Depth + OctoMap (single flow, TF-stable)

> Goal: fix the two real issues:
> 1) map only updates in front of drone (camera frame not transformed into map)
> 2) shading/ghost map while drone moves (TF not stable / delayed)

## 0) Root cause in one line

If `front_depth -> base_link -> map` is not continuously available with simulation time, `octomap_server` drops clouds and RViz map will look empty or only local/front updates.

---

## 1) Use ONE command flow only (no two modes)

This draft uses only:

- depth image + camera_info bridge
- `depth_image_proc` to `/depth/points`
- `octomap_server` subscribes `/depth/points`

No direct points mode here.

---

## 2) Terminal-by-terminal commands

## Terminal A — Gazebo

```bash
gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

## Terminal B — SITL + MAVProxy

```bash
cd /path/to/ardupilot
sim_vehicle.py -v ArduCopter -f gazebo-iris --console --map
```

## Terminal C — Bridge image + camera_info + /clock (must-have)

> If your camera topics are flat, use `/front_depth` and `/camera_info`.
> If world-scoped, replace with your exact `/world/.../image` and `/world/.../camera_info` from `gz topic -l`.

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  /clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock \
  /front_depth@sensor_msgs/msg/Image@gz.msgs.Image \
  /camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

## Terminal D — depth_image_proc -> point cloud

```bash
source /opt/ros/humble/setup.bash
ros2 run depth_image_proc point_cloud_xyz_node --ros-args \
  -r image_rect:=/front_depth \
  -r camera_info:=/camera_info \
  -r points:=/depth/points
```

## Terminal E — Publish camera extrinsic TF (must-have)

`front_depth` pose must match your SDF sensor pose:

```bash
source /opt/ros/humble/setup.bash
ros2 run tf2_ros static_transform_publisher \
  0.12 0 0.03 0 0 0 base_link front_depth
```

## Terminal F — Publish drone dynamic TF to map (must-have for global map)

Bridge Gazebo model pose to ROS TF (replace model name if not `sitl_iris`):

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  /model/sitl_iris/pose@tf2_msgs/msg/TFMessage@gz.msgs.Pose_V
```

> This is the critical step that keeps camera moving in map frame.

## Terminal G — Start octomap_server with sim time

```bash
source /opt/ros/humble/setup.bash
ros2 run octomap_server octomap_server_node --ros-args \
  -p use_sim_time:=true \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

---

## 3) RViz settings (or map will look empty)

1. `Fixed Frame` = `map`
2. `Add` -> `By topic` -> `/octomap_full`
3. Set RViz to sim time:

```bash
ros2 param set /rviz2 use_sim_time true
```

---

## 4) Avoid "Message Filter dropping ... queue is full"

Use all checks below before changing algorithm:

1. Ensure `/clock` is bridged and `octomap_server use_sim_time=true`.
2. Ensure both TF links exist:
   - dynamic `map -> base_link` (Terminal F)
   - static `base_link -> front_depth` (Terminal E)
3. Verify TF is continuous:

```bash
ros2 run tf2_tools view_frames
ros2 topic echo /tf --once
ros2 topic echo /tf_static --once
```

4. If still dropping, reduce cloud input rate at source (recommended): lower depth camera `update_rate` in SITL iris SDF (e.g., 15 -> 10).
5. Keep one OctoMap subscriber only (do not start multiple octomap_server instances).

---

## 5) Final verification sequence

```bash
# 1) Gazebo depth image has data
gz topic -e --topic /front_depth

# 2) ROS image and cloud have data
ros2 topic echo /front_depth --once
ros2 topic echo /depth/points --once
ros2 topic hz /depth/points

# 3) TF chain is valid (map/base_link/front_depth)
ros2 run tf2_tools view_frames

# 4) Octomap has output
ros2 topic echo /octomap_full --once
```

If step 3 is broken, step 4 will usually fail or only update in front of drone.
