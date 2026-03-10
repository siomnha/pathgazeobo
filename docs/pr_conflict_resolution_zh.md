# PR 冲突快速处理（针对本仓库）

如果你在 GitHub 上提示 *This branch has conflicts that must be resolved*，按下面做。

## 1) 本地同步主分支

```bash
git fetch origin
git checkout work
git rebase origin/main
```

> 如果你不是 `main`，把 `origin/main` 换成目标基线分支。

## 2) 解决冲突文件

查看冲突文件：

```bash
git status
```

逐个打开冲突文件，删除冲突标记：

- `<<<<<<< HEAD`
- `=======`
- `>>>>>>> <commit>`

完成后：

```bash
git add <conflicted_file_1> <conflicted_file_2>
git rebase --continue
```

重复到 rebase 结束。

## 3) 推送更新分支

```bash
git push --force-with-lease origin work
```

## 4) 本仓库最常见冲突点

本次改动里，最容易冲突的是这些文件：

- `goaero_mission3_v1.sdf`
- `scripts/patch_sitl_iris_depth_camera.sh`
- `docs/sitl_iris_harmonic_depth_flight_full_guide_zh.md`
- `docs/octomap_pipeline_zh.md`

建议优先保留以下事实：

1. world 使用 `model://iris` 且命名 `sitl_iris`。
2. `patch_sitl_iris_depth_camera.sh` 会**重写** `front_depth` 为标准结构（不是仅跳过）。
3. depth camera 参数使用标准 `<camera><image><clip>` 结构。

## 5) 一键检查（冲突解决后）

```bash
bash -n scripts/patch_sitl_iris_depth_camera.sh
bash -n scripts/run_iris_octomap_pipeline.sh
python - <<'PY'
import xml.etree.ElementTree as ET
ET.parse('goaero_mission3_v1.sdf')
print('world xml ok')
PY
```

如果以上命令通过，再回 GitHub 点 *Mark as resolved* / *Push* 即可。
