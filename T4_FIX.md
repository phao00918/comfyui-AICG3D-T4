## sm75 轮子版本（2026-11-03 更新）

本仓库现在就是 sm75 轮子版本，不是“官方 Sage + 门控”而已：

- 加载器里的注意力选项新增显式选项 **SageAttention2 sm75 轮子（T4）**，新节点默认就是这一项；旧工作流里选“自动（Sage 优先）”的，在 T4 上也会先试 sm75 轮子。
- 对接路径已核对：加载器（AICG3D_H3Loader）把 accel.py 的注意力控件合并进自己，load() 转成 AccelConfig 放进 bundle.accel，模型建好后 _LazyH3Model._finish() 调 apply_acceleration()，再由 _apply_attention() 调 model.clone().set_model_optimized_attention(func)。所以改 accel.py 就等于改了加载器的 Sage 行为，加载器本身不用另外改代码；ComfyUI 的 --use-sage-attention 只是全局默认，会被这个按模型补丁覆盖。
- 选 sm75 轮子必须同时满足：验证标记通过（cos>=0.999、seq4096 提速>=1.2x、torch 2.11.0）且装的确实是 sageattention 2.1.2 + torch 2.11.0+cu130，缺任何一点都明确回落 SDPA，不再把官方 Sage 打到模型上。

# T4（sm75）Sage 修复说明

## 原问题（一句话）

AICG3D 加载器里“自动（Sage 优先）”在 T4 上用不了：它只检查 Sage 后端
有没有在 ComfyUI 里注册，注册了就选 Sage。但官方 SageAttention 内核
锁死 sm80+，在 sm75 上装了也会在采样时静默回落到 PyTorch，并满屏刷
`[ERROR] Error running sage attention: PassManager::run failed`。
结果是：界面上显示选了 Sage，实际没加速，日志还被错误刷满。

## 本仓库改了什么（只有三处，其余代码未动）

1. **`aicg3d_h3easy/accel.py`（核心修复）**
   - 新增 `_is_sm75()`（CUDA capability major == 7）和
     `_sage_sm75_marker_verified()`（读验证标记）。
   - 自动模式和手动选 Sage 时，在 sm75 上只有验证标记通过才选 Sage；
     否则明确回落到 SDPA，并写清楚原因，不再把坏的 Sage 打到模型上。
   - 非 sm75（sm80+）的机器保持上游原逻辑不变。
   - 注意力控件的提示文字也同步改了，说明 T4 这条例外规则。

2. **`scripts/verify_sage_sm75.py`（新增，验证关口）**
   - 只验证，不下载轮子（轮子由部署脚本装）。
   - 要求：GPU 是 sm75、torch 是 2.11.0+cu130、Sage 能导入。
   - 在 H3 真实形状（heads=56、head_dim=128）下跑 SDPA 对比：
     seq=1024 和 seq=4096，cos >= 0.999 且 seq=4096 提速 >= 1.2x 才算通过。
   - 通过才写 `t4_sage_sm75_verified.json`；不过就删掉旧标记并退出非 0，
     部署脚本收到失败也不会中断整个部署，只是 Sage 这条路不开。

3. **`deploy_t4.sh` / `kaggle_t4.ipynb` / `PINNED_VERSIONS.md`（新增，傻瓜式部署）**
   - 锁死 ComfyUI commit、torch 2.11.0+cu130、Sage 轮子、ComfyUI 新依赖版本。
   - 按顺序：装 torch → 拉固定版 ComfyUI → 把本仓库拷到
     `ComfyUI/custom_nodes/comfyui-AICG3D` → 装 fp16_fix → 下载模型并逐个
     校验 >100MB → 装 Sage 轮子并跑验证 → 只有标记通过才带
     `--use-sage-attention` 启动，否则不带这个开关走 SDPA。
   - 启动参数固定：normalvram + `--disable-pinned-memory`
     + `--preview-method none` + `--fp16-unet`。

## 2026-11-02 实测数据（这次修复的依据，不是新 claims）

- 路线：sm75 SageAttention2 2.1.2 + torch 2.11.0+cu130 + `--use-sage-attention`。
- 数值：cos 0.999927；合成基准 SDPA 43.73ms 对 Sage 23.31ms（约 1.88x）。
- 端到端 10 秒：3986 秒，比原始 5031 秒少 20.8%，没有达到减半。
  原因是合成提速没有完全转化为端到端提速（MLP、权重分阶段加载、
  VAE/文本编码、CPU-GPU 搬运占大头）。所以本修复只承诺“在 T4 上 Sage
  真正用起来、不再假加速”，不承诺减半，步数保持 20 步不变。

## 来源与许可证

- 上游：JGRFW/comfyui-AICG3D，v1.1.24，GPL-3.0-or-later，LICENSE 原文件保留。
- 骨架来源（上游自述）：ComfyUI-MiniMaxH3-Easy（nkxx188，MIT）、
  Goohai-MiniMax-H3_Integration（goohai）。
- 本仓库是独立快照，不是上游 fork；改动部分同样按 GPL-3.0-or-later 开源，
  上游作者和来源信息在 README / ACKNOWLEDGEMENTS.md 里保留，未冒充原创。
