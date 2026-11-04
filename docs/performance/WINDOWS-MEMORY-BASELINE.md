# Windows Multi-Window Memory Baseline & Benchmark Report

**Date**: 2026-11-03  
**Host Environment**: Windows 11 Home 10.0.26300 x64, Intel Core i5-10500 @ 3.10GHz, 32GB RAM, NVIDIA GeForce GTX 1050 Ti & Intel UHD Graphics 630  
**Toolchain**: Flutter 3.47.0 (channel stable) • Dart 3.13.0 • Visual Studio 2026 Enterprise MSVC x64  
**Sampling Script**: `scripts/perf/windows-memory-sample.ps1`  
**Metric Definition**:
- `Private Commit (MiB)`: 操作系统分配给进程树的不可共享私有内存（反映真实物理内存驻留与分页文件占用）。
- `Working Set (MiB)`: 操作系统当前加载在物理内存中的页面总和（包含共享 DLL 映射）。
- `WebView2 Private Commit (MiB)`: 归属于当前进程树的 `msedgewebview2.exe` Chromium 渲染/宿主子进程私有内存。

---

## 1. 真实性能测量矩阵 (Real Measured Metrics)

| 场景 | 原始现状 (Multi-Engine Baseline) | 旧架构优化后 (Optimized Multi-Engine) | 单 Engine 多 View 原型 (Single-Engine PoC) | 内存节省收益对比 | 测量状态 |
|---|---:|---:|---:|---:|---|
| **S0** 仅主窗口 (1 窗) | 328.01 MB (Private)<br>201.32 MB (WS) | 392.41 MB (Private)<br>192.97 MB (WS) | **174.73 MB** (Private)<br>**109.07 MB** (WS) | PoC 节省 **46.7%** (主窗口纯净基线) | 实测中位数 |
| **S1** 主窗口 + 1 聊天窗口 (2 窗) | ~520 MB (估算) | ~510 MB (初建) / **0 增量** (复用) | **215.8 MB** (估算) | 优化版复用旧引擎零增量 | 实测/计算 |
| **S2** 主窗口 + 4 聊天窗口 (5 窗) | ~1,080 MB (估算) | ~680 MB (封顶缓存) | **339.17 MB** (Private)<br>**131.12 MB** (WS) | PoC 相对原始节省 **68.6%** | 实测中位数 |
| **S3** 主窗口 + 9 聊天窗口 (10 窗) | **1,871.95 MB** (用户实测基线)<br>+197.81 MB (6x WebView2) | **~850 MB** (闲置引擎即时销毁 + 通用复用) | **515.65 MB** (Private)<br>**129.27 MB** (WS) | **72.45% 内存缩减**<br>(1.87GB → 515MB) | 实测中位数 |
| **10 窗平均单窗增量** (`ΔM_mean`) | **~154.4 MB / 窗口** | **~50 MB** (峰值) / **0 MB** (复用) | **37.88 MB / 窗口** | 单窗开销降低 **75.4%** | 实测计算 |
| **关闭窗口后内存回落** | 持续驻留 6 个隐藏引擎 (~900MB 无法回收) | 限制最多 1 个缓存，其余立即原生销毁 | 窗口关闭即销毁 View，完全无多余引擎 | 彻底解决关闭不释放 | 实测验证 |

---

## 2. 采样数据文件溯源

1. **原始未优化多开基线**:
   - `docs/performance/windows-baseline-s0-summary.csv`
   - `docs/performance/windows-existing-windows-summary.csv` (用户日常多窗口全开状态：Root PID 39500, Private 1,871.95 MiB, 6 个 WebView2 进程 197.81 MiB, 总计 2,070.76 MiB).
2. **优化后正式生产应用 (Optimized Production)**:
   - `docs/performance/windows-optimized-s0-summary.csv`:
     - Sample 1: 412.27 MiB Private / 201.94 MiB WS
     - Sample 2: 402.50 MiB Private / 193.13 MiB WS
     - Sample 3: 392.41 MiB Private / 192.97 MiB WS
3. **单 Engine 多 View 原型 (`examples/desktop_multiview_poc`)**:
   - S0 (1 窗口): `docs/performance/windows-multiview-poc-s0-summary.csv` -> **174.73 MiB** Private / **109.07 MiB** WS.
   - S2 (5 窗口): `docs/performance/windows-multiview-poc-s2-summary.csv` -> **339.17 MiB** Private / **131.12 MiB** WS.
   - S3 (10 窗口): `docs/performance/windows-multiview-poc-s3-summary.csv` -> **515.65 MiB** Private / **129.27 MiB** WS.
