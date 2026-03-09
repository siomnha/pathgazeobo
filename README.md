# pathgazeobo

这个仓库现在包含你的 Gazebo 世界文件（`goaero_mission3_v1.sdf`），并补充了一份从 **ArduPilot SITL + Gazebo Sim + ROS 2** 生成 **OctoMap** 的实战指南。

## 快速入口

- 世界文件：`goaero_mission3_v1.sdf`
- OctoMap 管线指南（含“无消息”排障）：`docs/octomap_pipeline_zh.md`
- Iris 一键脚本（支持 `image_proc` / `points_direct`）：`scripts/run_iris_octomap_pipeline.sh`
- 最小演示脚本：`scripts/run_octomap_pipeline.sh`

> 说明：请先用 `gz topic -l` 找到 **完整** depth 话题路径，再填到脚本/命令里。
