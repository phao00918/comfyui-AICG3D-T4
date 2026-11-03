# 锁死版本清单（本仓库的核心承诺）

本仓库是一个**独立快照**，不是上游 JGRFW/comfyui-AICG3D 的 fork 跟随。
以后上游再怎么更新，都不会动到这份代码；部署脚本也不会去拉最新版、
不会 `git pull`，只用下面这些固定版本。只要这份清单不变，同一套部署
命令在以后拉到的就是同一套能跑的组合。

| 项目 | 锁死版本 | 说明 |
|---|---|---|
| AICG3D 代码 | 本仓库快照，基于上游 v1.1.24（2026-11-03 拉取） | 唯一改动见 `T4_FIX.md`，其余代码未动 |
| ComfyUI | commit `ab08f7b2caa6d4007ecde3762116c6193613f43b`（2026-11-03 master） | 部署脚本用 codeload tarball 拉这个 commit，不拉 master 最新 |
| Python | Kaggle 默认 Python 3（cp312 或 cp313，脚本自动识别） | Sage 轮子按 cp 标签选，cp312 和 cp313 各有一份 |
| PyTorch | `torch==2.11.0+cu130`，`torchvision==0.26.0+cu130`，`torchaudio==2.11.0+cu130` | sm75 Sage 轮子只对应这个版本，不要升到 2.14 |
| SageAttention | `sageattention==2.1.2`，sm75 专用轮子（netrunner-exe 优化版） | 见 `scripts/verify_sage_sm75.py`，验证不过就回落 SDPA |
| ComfyUI 新依赖 | `comfy-aimdo==0.6.0`，`torchsde`，`comfy-kitchen==0.2.40`，`av==19.0.2` | 后两项是 2026-11-03 实测里新版 ComfyUI 启动缺的依赖 |
| fp16_fix | Amduraznak `minimax_h3_fp16_fix.py`，校验 >1000 字节且含 `MiniMaxH3Model` | 启动必须带 `--fp16-unet` 才激活 |
| 模型 | `Comfy-Org/MiniMax-H3`，full 清单（见部署脚本） | FL2VA 出现两次是故意的绕 bug 做法，不要去重 |
| 启动参数 | normalvram + `--disable-pinned-memory` + `--preview-method none` + `--fp16-unet`（Sage 验证通过时才加 `--use-sage-attention`） | 不要用 lowvram 当默认档；不要用 `--reserve-vram 0.8` 的老参数 |

## Sage 轮子地址（部署脚本自动下载，用户不用手动找）

- cp313：`https://github.com/netrunner-exe/SageAttention2-Colab-Wheels/raw/main/optimized_wheels/colab-torch-cp313-2.11.0%2Bcu130/sageattention-2.1.2-cp313-cp313-linux_x86_64.whl`
- cp312：把上面路径里的 `cp313` 换成 `cp312`（`colab-torch-cp312-2.11.0+cu130/sageattention-2.1.2-cp312-cp312-linux_x86_64.whl`）

安装一律 `--no-deps`，不让它顺带升级 torch。

## 本仓库没有包含的东西（部署脚本会另外处理或明确提示）

- Spark-TTS 参考音频（`aicg3d_sparktts/assets/Step-Audio-speakers/*.wav`）：二进制文件，
  只影响角色音色库的试听参考，不影响视频生成；需要时请从上游仓库单独下载。
- 上游的 GitHub Actions（`.github/`）：本仓库是独立快照，不自动发布、不自动跟随上游，
  所以不带这套流程。
- 模型权重、ComfyUI 本体：都不在仓库里，部署脚本按上面锁死的版本另外下载，
  这样仓库本身保持轻量、可审查。
