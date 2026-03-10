# Draft Pipeline (Fixed): Iris + Depth + OctoMap with Correct TF for Moving Drone

> Goal: fix mapping smear/ghosting when drone is moving by using the correct TF chain.

## 0) Why smear happens

When the drone moves, OctoMap must transform each incoming point cloud from camera frame into a stable world frame.
If `map -> base_link` is missing / unstable, or `base_link -> front_depth` is missing, the map looks like camera is fixed in front and creates shading/ghost artifacts.

## 1) Required TF chain

For **global map while moving**:

- `map -> base_link` (dynamic, from your localization / state estimation)
- `base_link -> front_depth` (static camera extrinsic)

If dynamic `map -> base_link` is not ready yet, use fallback:

- set OctoMap `frame_id:=base_link` (local body map, stable but not global)

---

## 2) Run commands (image_proc path, no pipeline_mode)

### Terminal A: Gazebo

```bash
gz sim -r /workspace/pathgazeobo/goaero_mission3_v1.sdf
```

### Terminal B: SITL + MAVProxy

```bash
cd /path/to/ardupilot
sim_vehicle.py -v ArduCopter -f gazebo-iris --console --map
```

### Terminal C: Bridge depth image + camera_info

If your topics are flat:

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  /front_depth@sensor_msgs/msg/Image@gz.msgs.Image \
  /camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo
```

If your topics are world-scoped, replace with your real paths from `gz topic -l`.

### Terminal D: depth_image_proc -> point cloud

```bash
source /opt/ros/humble/setup.bash
ros2 run depth_image_proc point_cloud_xyz_node --ros-args \
  -r image_rect:=/front_depth \
  -r camera_info:=/camera_info \
  -r points:=/depth/points
```

### Terminal E: camera static TF (`base_link -> front_depth`)

```bash
source /opt/ros/humble/setup.bash
ros2 run tf2_ros static_transform_publisher \
  0.12 0 0.03 0 0 0 base_link front_depth
```

### Terminal F: octomap_server

#### Option 1 (recommended for moving drone + global map)
Use this only when dynamic `map -> base_link` already exists:

```bash
source /opt/ros/humble/setup.bash
ros2 run octomap_server octomap_server_node --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=map \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

#### Option 2 (fallback to remove smear immediately)
If dynamic `map -> base_link` is not ready:

```bash
source /opt/ros/humble/setup.bash
ros2 run octomap_server octomap_server_node --ros-args \
  -p resolution:=0.15 \
  -p frame_id:=base_link \
  -p sensor_model/max_range:=20.0 \
  -r cloud_in:=/depth/points
```

---

## 3) Verify TF before blaming octomap

```bash
source /opt/ros/humble/setup.bash
ros2 run tf2_tools view_frames
ros2 topic echo /tf --once
ros2 topic echo /tf_static --once
```

And verify data path:

```bash
gz topic -e --topic /front_depth
ros2 topic echo /front_depth --once
ros2 topic echo /depth/points --once
ros2 topic hz /depth/points
ros2 topic echo /octomap_full --once
```

## 4) Minimal anti-smear checklist

1. `base_link -> front_depth` exists and matches SDF camera pose.
2. For global map, dynamic `map -> base_link` is continuous.
3. `octomap_server frame_id` is consistent with TF tree.
4. Do not mix points_direct checks with image_proc topics in the same run.
