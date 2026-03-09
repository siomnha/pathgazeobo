#!/usr/bin/env bash
set -euo pipefail

# 为 ArduPilot SITL/Gazebo 的 iris 模型自动注入 depth_camera 传感器。
# 用法：
#   ./scripts/patch_sitl_iris_depth_camera.sh /path/to/ardupilot_gazebo
# 或：
#   MODEL_SDF=/path/to/model.sdf ./scripts/patch_sitl_iris_depth_camera.sh

REPO_PATH="${1:-}"
MODEL_SDF="${MODEL_SDF:-}"

if [[ -z "$MODEL_SDF" ]]; then
  if [[ -z "$REPO_PATH" ]]; then
    echo "[ERROR] 请传入 ardupilot_gazebo 路径，或设置 MODEL_SDF。"
    exit 1
  fi

  CANDIDATE_1="$REPO_PATH/models/iris/model.sdf"
  CANDIDATE_2="$REPO_PATH/models/iris_with_standoffs/model.sdf"

  if [[ -f "$CANDIDATE_1" ]]; then
    MODEL_SDF="$CANDIDATE_1"
  elif [[ -f "$CANDIDATE_2" ]]; then
    MODEL_SDF="$CANDIDATE_2"
  else
    echo "[ERROR] 在 $REPO_PATH 下未找到 iris model.sdf。"
    echo "        请手动指定 MODEL_SDF=/absolute/path/to/model.sdf"
    exit 1
  fi
fi

if [[ ! -f "$MODEL_SDF" ]]; then
  echo "[ERROR] MODEL_SDF 不存在: $MODEL_SDF"
  exit 1
fi

python - "$MODEL_SDF" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

model_sdf = Path(sys.argv[1])
text = model_sdf.read_text(encoding='utf-8')

root = ET.fromstring(text)
model = root.find('model')
if model is None:
    raise SystemExit('[ERROR] 未找到 <model> 节点。')

link = model.find("link[@name='base_link']")
if link is None:
    links = model.findall('link')
    if not links:
        raise SystemExit('[ERROR] 未找到任何 <link> 节点。')
    link = links[0]

for s in link.findall('sensor'):
    if s.get('name') == 'front_depth':
        print('[INFO] 已存在 front_depth 传感器，跳过修改。')
        raise SystemExit(0)

sensor = ET.Element('sensor', {'name': 'front_depth', 'type': 'depth_camera'})
ET.SubElement(sensor, 'pose').text = '0.12 0 0.03 0 0 0'
ET.SubElement(sensor, 'always_on').text = '1'
ET.SubElement(sensor, 'update_rate').text = '15'
ET.SubElement(sensor, 'topic').text = '/front_depth'
ET.SubElement(sensor, 'visualize').text = 'true'

camera = ET.SubElement(sensor, 'camera')
ET.SubElement(camera, 'horizontal_fov').text = '1.047'
image = ET.SubElement(camera, 'image')
ET.SubElement(image, 'width').text = '640'
ET.SubElement(image, 'height').text = '480'
ET.SubElement(image, 'format').text = 'R_FLOAT32'
clip = ET.SubElement(camera, 'clip')
ET.SubElement(clip, 'near').text = '0.15'
ET.SubElement(clip, 'far').text = '20.0'

link.append(sensor)

backup = model_sdf.with_suffix(model_sdf.suffix + '.bak')
backup.write_text(text, encoding='utf-8')

ET.indent(root, space='  ')
model_sdf.write_text(ET.tostring(root, encoding='unicode'), encoding='utf-8')
print(f'[OK] 已注入 front_depth 到: {model_sdf}')
print(f'[OK] 备份文件: {backup}')
PY
