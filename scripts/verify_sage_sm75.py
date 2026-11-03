#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T4（sm75）Sage 验证脚本。

用途：只有这支脚本跑通并写出验证标记，aicg3d_h3easy/accel.py 在 sm75 上
才会把 Sage 打到模型上。官方 SageAttention 在 sm75 上装了也会静默回落，
所以“装了包”不算通过，必须同时满足数值和速度两项：

* 数值：Sage 输出与 SDPA 输出的 cos >= 0.999（H3 形状：heads=56, head_dim=128）
* 速度：seq=4096 时 Sage 比 SDPA 快 >= 1.2x（否则等于没加速，不值得冒风险）

轮子（部署脚本会先装好，本脚本只验证不下载）：
  SageAttention2 2.1.2，sm75 专用，torch 2.11.0+cu130，cp312/cp313，Linux
  来源：netrunner-exe/SageAttention2-Colab-Wheels，optimized_wheels
  例（cp313）：optimized_wheels/colab-torch-cp313-2.11.0+cu130/
              sageattention-2.1.2-cp313-cp313-linux_x86_64.whl

用法：
    python scripts/verify_sage_sm75.py [--marker PATH]

成功：写出标记 JSON，退出 0。
失败：删除旧标记（如果存在），打印清楚原因，退出非 0。
    失败不等于不能生成视频，只表示 Sage 这条路在当前机器上不可用，
    accel.py 会自动回落到 SDPA。
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

MIN_COS = 0.999
MIN_SPEEDUP_4096 = 1.2
REQUIRED_TORCH = "2.11.0"


def fail(message: str, marker: Path | None = None) -> int:
    print(f"[verify_sage_sm75] FAIL: {message}")
    if marker is not None:
        try:
            marker.unlink(missing_ok=True)
        except Exception:
            pass
    return 1


def bench(fn, q, k, v, iters: int) -> tuple[object, float]:
    import torch

    for _ in range(3):
        fn(q, k, v)
    torch.cuda.synchronize()
    t0 = time.time()
    for _ in range(iters):
        out = fn(q, k, v)
    torch.cuda.synchronize()
    return out, (time.time() - t0) / iters * 1000.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--marker",
        default=str(Path(__file__).resolve().parents[1] / "t4_sage_sm75_verified.json"),
        help="验证标记写出路径（默认：仓库根目录 t4_sage_sm75_verified.json）",
    )
    args = parser.parse_args()
    marker = Path(args.marker)

    import torch

    if not torch.cuda.is_available():
        return fail("CUDA 不可用", marker)
    cap = torch.cuda.get_device_capability(0)
    print(f"[verify_sage_sm75] GPU: {torch.cuda.get_device_name(0)}, capability: {cap}")
    if cap[0] != 7:
        return fail(f"不是 Turing sm75（capability={cap}），本脚本只验证 T4/sm75 路线", marker)
    print(f"[verify_sage_sm75] torch: {torch.__version__}, cuda: {torch.version.cuda}")
    if not torch.__version__.startswith(REQUIRED_TORCH):
        return fail(
            f"torch 必须是 {REQUIRED_TORCH}+cu130（sm75 轮子只对应这个版本），"
            f"当前是 {torch.__version__}，请先按部署脚本降回 2.11.0",
            marker,
        )

    try:
        from sageattention import sageattn
    except Exception as exc:
        return fail(f"无法导入 sageattention（轮子没装或版本不对）：{exc!r}", marker)

    try:
        import importlib.metadata

        sage_version = importlib.metadata.version("sageattention")
    except Exception:
        sage_version = "unknown"
    print(f"[verify_sage_sm75] sageattention: {sage_version}")

    results = {}
    try:
        for seq, iters in ((1024, 20), (4096, 10)):
            q = torch.randn(1, 56, seq, 128, device="cuda:0", dtype=torch.float16)
            k = torch.randn(1, 56, seq, 128, device="cuda:0", dtype=torch.float16)
            v = torch.randn(1, 56, seq, 128, device="cuda:0", dtype=torch.float16)

            def sdpa_fn(a, b, c):
                return torch.nn.functional.scaled_dot_product_attention(a, b, c, is_causal=False)

            out_sdpa, dt_sdpa = bench(sdpa_fn, q, k, v, iters)
            out_sage, dt_sage = bench(lambda a, b, c: sageattn(a, b, c), q, k, v, iters)
            cos = torch.nn.functional.cosine_similarity(
                out_sdpa.flatten(), out_sage.flatten(), dim=0
            ).item()
            speedup = dt_sdpa / dt_sage if dt_sage > 0 else 0.0
            print(
                f"[verify_sage_sm75] seq={seq}: SDPA {dt_sdpa:.2f}ms, "
                f"Sage {dt_sage:.2f}ms, speedup={speedup:.2f}x, cos={cos:.6f}"
            )
            results[seq] = {"cos": cos, "speedup": speedup, "sdpa_ms": dt_sdpa, "sage_ms": dt_sage}
            del q, k, v, out_sdpa, out_sage
            torch.cuda.empty_cache()
    except Exception as exc:
        return fail(f"基准测试失败（可能是显存不足或内核不兼容）：{exc!r}", marker)

    cos_4096 = results[4096]["cos"]
    speedup_4096 = results[4096]["speedup"]
    if cos_4096 < MIN_COS:
        return fail(f"数值验证不过：seq4096 cos={cos_4096:.6f} < {MIN_COS}", marker)
    if speedup_4096 < MIN_SPEEDUP_4096:
        return fail(
            f"速度验证不过：seq4096 提速={speedup_4096:.2f}x < {MIN_SPEEDUP_4096}x，"
            "说明这支 Sage 在当前机器上没有真实加速，不值得用",
            marker,
        )

    marker.parent.mkdir(parents=True, exist_ok=True)
    import datetime

    data = {
        "verified": True,
        "cos": cos_4096,
        "cos_1024": results[1024]["cos"],
        "speedup_4096": speedup_4096,
        "speedup_1024": results[1024]["speedup"],
        "torch": torch.__version__,
        "sageattention": sage_version,
        "device": torch.cuda.get_device_name(0),
        "device_capability": f"{cap[0]}.{cap[1]}",
        "verified_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    marker.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"[verify_sage_sm75] PASS: 标记已写到 {marker}")
    print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
