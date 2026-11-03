# 傻瓜式部署（T4 / Kaggle）

本仓库是 AICG3D 短剧工作台的独立快照，已做 T4（sm75）Sage 修复，
版本全部锁死，不跟随上游更新。以后部署就按下面三步走，不用再去
上游 JGRFW 仓库拉代码，也不用手动拼版本。

## 一、拉取本仓库

```bash
git clone https://github.com/phao00918/comfyui-AICG3D-T4.git
cd comfyui-AICG3D-T4
```

仓库是公开的，Kaggle 和本地都不用填 token 就能拉。

## 二、选一种方式启动

### 方式 A：Kaggle（推荐，和你现在用的环境一样）

1. Kaggle 上新建私人草稿，选 GPU T4x2、Internet 开。
2. 先在一个格子里跑：
   ```bash
   !git clone https://github.com/phao00918/comfyui-AICG3D-T4.git /kaggle/working/aicg3d-t4-repo
   ```
3. 再把本仓库里的 `kaggle_t4.ipynb` 的格子按顺序贴进来（第 1-5 格），
   不要跳格，不要改配置（normalvram、full、torch 2.11.0+cu130 都是写死的）。
4. 第 5 格会给出 Cloudflare 隧道 URL，打开就是 ComfyUI。

### 方式 B：Linux 服务器 / 本地 Linux

```bash
bash deploy_t4.sh --workdir /kaggle/temp/h3_project
```

脚本会自动：装 torch 2.11.0+cu130 → 拉固定版 ComfyUI →
把本仓库拷到 `custom_nodes/comfyui-AICG3D` → 装 fp16_fix →
下载模型并校验 → 装 Sage 轮子并验证 → 启动 ComfyUI + 隧道，
最后打印隧道 URL。

## 三、在 ComfyUI 里用

- 右键菜单找 **AICG3D** 分类。
- 导入 `workflows/` 里的 13 号无限分段工作流，上传图片，
  核对时长、步数（保持 20 步）、分辨率、种子，点 Queue。
- 注意力加速默认是“自动（Sage 优先）”，在 T4 上只有验证通过才
  真正走 Sage，否则自动回落 SDPA，不会再刷 PassManager 错误。
- 生成期间每 20 分钟动一下 Kaggle（跑第 6 格核查），超过 40 分钟
  无改动 Kaggle 会让会话离线，临时目录里的东西会消失。
- 生成完先把视频下载到本地，不要只留在 Kaggle 的 working 里。

## 版本锁死清单

见 `PINNED_VERSIONS.md`。修复细节见 `T4_FIX.md`。
许可证：GPL-3.0-or-later（上游 LICENSE 原文件保留），
上游来源：JGRFW/comfyui-AICG3D v1.1.24。
