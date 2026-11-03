#!/usr/bin/env bash
# AICG3D T4 傻瓜式部署：拉本仓库 -> 固定版 ComfyUI -> 下载模型 -> 启动。
# 用法（先把本仓库 clone 到本地，再在仓库根目录运行）：
#   bash deploy_t4.sh [--workdir /kaggle/temp/h3_project] [--vram-mode normalvram]
# Kaggle 上 workdir 默认就是 /kaggle/temp/h3_project；本地默认是 ./h3_project。
# 本脚本不拉最新版、不 git pull，只用 PINNED_VERSIONS.md 里锁死的版本。
set -euo pipefail

WORKDIR="${WORKDIR:-/kaggle/temp/h3_project}"
VRAM_MODE="${VRAM_MODE:-normalvram}"
COMFYUI_SHA="ab08f7b2caa6d4007ecde3762116c6193613f43b"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --vram-mode) VRAM_MODE="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

COMFY="$WORKDIR/ComfyUI"
MODEL_ROOT="$COMFY/models"
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR" "$MODEL_ROOT"

echo "== 1. GPU 检查 =="
nvidia-smi || true
python3 -c "import torch; print('torch', torch.__version__); print('cuda', torch.cuda.is_available()); [print(i, torch.cuda.get_device_name(i), torch.cuda.get_device_capability(i)) for i in range(torch.cuda.device_count())]" || true

echo "== 2. 装 torch 2.11.0+cu130（Sage 轮子只对应这个版本，不要升） =="
python3 -m pip install "torch==2.11.0+cu130" "torchvision==0.26.0+cu130" "torchaudio==2.11.0+cu130" --index-url https://download.pytorch.org/whl/cu130
python3 -m pip install --upgrade huggingface-hub "huggingface-hub>=1.5.0,<2.0" hf_transfer

echo "== 3. 拉固定版 ComfyUI（commit $COMFYUI_SHA，不拉 master） =="
if [ -f "$WORKDIR/.comfyui_pinned_sha" ] && [ "$(cat "$WORKDIR/.comfyui_pinned_sha")" = "$COMFYUI_SHA" ] && [ -f "$COMFY/main.py" ]; then
  echo "ComfyUI 已是锁死版本，跳过下载。"
else
  rm -rf "$COMFY"
  curl -L -o /tmp/comfyui.tar.gz "https://codeload.github.com/comfyanonymous/ComfyUI/tar.gz/$COMFYUI_SHA"
  mkdir -p "$WORKDIR/comfyui_tmp"
  tar -xzf /tmp/comfyui.tar.gz -C "$WORKDIR/comfyui_tmp"
  mv "$WORKDIR/comfyui_tmp/ComfyUI-$COMFYUI_SHA" "$COMFY"
  rmdir "$WORKDIR/comfyui_tmp"
  echo "$COMFYUI_SHA" > "$WORKDIR/.comfyui_pinned_sha"
fi
python3 -m pip install -r "$COMFY/requirements.txt"
python3 -m pip install "comfy-aimdo==0.6.0" torchsde "comfy-kitchen==0.2.40" "av==19.0.2"

echo "== 4. 把本仓库装到 custom_nodes（不拉上游，不 git pull） =="
rm -rf "$COMFY/custom_nodes/comfyui-AICG3D"
cp -a "$REPO_DIR" "$COMFY/custom_nodes/comfyui-AICG3D"
rm -rf "$COMFY/custom_nodes/comfyui-AICG3D/.git"

echo "== 5. 装 fp16_fix（校验后才放进去） =="
PATCH_URL="https://raw.githubusercontent.com/Amduraznak/minimax-h3-fp16-fix/main/minimax_h3_fp16_fix.py"
PATCH_FILE="$COMFY/custom_nodes/minimax_h3_fp16_fix.py"
curl -L -o /tmp/minimax_h3_fp16_fix.py "$PATCH_URL"
python3 - "$PATCH_FILE" << 'PYEOF'
import sys
from pathlib import Path
data = Path("/tmp/minimax_h3_fp16_fix.py").read_bytes()
assert len(data) > 1000 and b"MiniMaxH3Model" in data, "fp16_fix 校验失败"
Path(sys.argv[1]).write_bytes(data)
print("fp16_fix OK:", sys.argv[1], len(data), "bytes")
PYEOF

echo "== 6. 装 AICG3D 依赖 =="
python3 -m pip install -r "$COMFY/custom_nodes/comfyui-AICG3D/requirements.txt" || true
python3 -m pip install imageio-ffmpeg psutil requests aiohttp || true

echo "== 7. 下载模型（full 清单，FL2VA 两次是故意的，不要去重） =="
mkdir -p "$MODEL_ROOT/diffusion_models" "$MODEL_ROOT/text_encoders" "$MODEL_ROOT/vae" "$MODEL_ROOT/loras"
HF_HOME="$WORKDIR/hf_home" HF_HUB_ENABLE_HF_TRANSFER=1 \
  hf download Comfy-Org/MiniMax-H3 --local-dir "$MODEL_ROOT" --include \
  "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
  "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
  "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
  "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
  "vae/minimax_h3_video_vae_fp16.safetensors" \
  "vae/minimax_h3_audio_vae_fp32.safetensors" \
  "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
  "loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"
python3 - "$MODEL_ROOT" << 'PYEOF'
import sys
from pathlib import Path
root = Path(sys.argv[1])
files = [
  "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors",
  "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors",
  "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors",
  "vae/minimax_h3_video_vae_fp16.safetensors",
  "vae/minimax_h3_audio_vae_fp32.safetensors",
  "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors",
  "loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors",
]
ok = True
for f in files:
    p = root / f
    size = p.stat().st_size if p.exists() else 0
    print(f"  {f}: {size} bytes {'OK' if size > 100_000_000 else 'FAIL'}")
    ok = ok and size > 100_000_000
assert ok, "模型校验失败：有文件缺失或过小，不要启动 ComfyUI"
print("模型校验通过。")
PYEOF

echo "== 8. 装 sm75 Sage 轮子并验证（验证不过就回落 SDPA，不中断部署） =="
CP_TAG=$(python3 -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')")
echo "Python tag: $CP_TAG"
SAGE_URL="https://github.com/netrunner-exe/SageAttention2-Colab-Wheels/raw/main/optimized_wheels/colab-torch-${CP_TAG}-2.11.0%2Bcu130/sageattention-2.1.2-${CP_TAG}-${CP_TAG}-linux_x86_64.whl"
MARKER="$COMFY/custom_nodes/comfyui-AICG3D/t4_sage_sm75_verified.json"
rm -f "$MARKER"
SAGE_OK=0
if curl -L -o /tmp/sage_wheel.whl "$SAGE_URL" && python3 -m pip install --no-deps /tmp/sage_wheel.whl; then
  if python3 "$COMFY/custom_nodes/comfyui-AICG3D/scripts/verify_sage_sm75.py" --marker "$MARKER"; then
    SAGE_OK=1
    echo "Sage 验证通过，启动时会带 --use-sage-attention。"
  else
    echo "警告：Sage 验证没通过，启动时不带 --use-sage-attention，走 SDPA。"
  fi
else
  echo "警告：Sage 轮子下载/安装失败（可能是 Python 版本没有对应轮子），走 SDPA。"
fi

echo "== 9. 启动 ComfyUI =="
ARGS=(python3 main.py --listen 127.0.0.1 --port 8188)
if [ "$VRAM_MODE" = "highvram" ]; then ARGS+=(--highvram); fi
if [ "$VRAM_MODE" = "lowvram" ]; then ARGS+=(--lowvram); fi
ARGS+=(--disable-pinned-memory --preview-method none --fp16-unet)
if [ "$SAGE_OK" = "1" ]; then ARGS+=(--use-sage-attention); fi
echo "启动命令：${ARGS[*]}"
cd "$COMFY"
setsid nohup "${ARGS[@]}" > "$LOGDIR/comfyui.log" 2>&1 &
echo $! > "$WORKDIR/comfyui.pid"
for i in $(seq 1 36); do
  sleep 5
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8188),timeout=2); s.close()" 2>/dev/null; then
    echo "ComfyUI 已就绪（约 $((i*5)) 秒），PID: $(cat "$WORKDIR/comfyui.pid")，日志: $LOGDIR/comfyui.log"
    break
  fi
  if [ "$i" = "36" ]; then echo "警告：180 秒内端口 8188 未就绪，请看日志：$LOGDIR/comfyui.log"; fi
done

echo "== 10. 启动 Cloudflare 隧道（Quick Tunnel，无鉴权，URL 不要转发） =="
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -L -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/download/2024.10.0/cloudflared-linux-amd64.deb || true
  dpkg -i /tmp/cloudflared.deb || true
fi
if command -v cloudflared >/dev/null 2>&1; then
  setsid nohup cloudflared tunnel --url http://127.0.0.1:8188 > "$LOGDIR/cloudflared.log" 2>&1 &
  sleep 20
  grep -o 'https://[^ ]*trycloudflare.com[^ ]*' "$LOGDIR/cloudflared.log" | tail -1 || true
  echo "完整隧道日志：$LOGDIR/cloudflared.log"
else
  echo "cloudflared 不可用，请手动安装固定版本 2024.10.0 后再跑隧道。"
fi
echo "部署完成。ComfyUI 在 http://127.0.0.1:8188，AICG3D 在右键菜单 AICG3D 分类里。"
