# Windows memory baseline

The pre-existing Release executable exited with code 1 on 2026-11-03. A fresh `flutter build windows --release` succeeded (134.6 s), and the rebuilt application launched. One main-window run was sampled three times, five seconds apart. It used the existing signed-in account and visible session list; no test chat was opened. This is a preliminary sample, not three independent runs, and hidden/prewarmed engines have not been enumerated.

Environment: Windows 11 Home 10.0.26300 x64, Intel i5-10500, 34,093,867,008 bytes physical RAM, NVIDIA GTX 1050 Ti and Intel UHD 630; Flutter 3.47.0, Dart 3.13.0. Source commit at build: `26eb2a1`; display/DPI not recorded.

The sampler was smoke-tested against its own PowerShell process, not the application. Example, after launching the verified Release executable and recording its PID:

```powershell
.\scripts\perf\windows-memory-sample.ps1 -RootPid <PID> -Scenario S0 -Iteration 1 -WindowCount 1 -Count 6 -IntervalSeconds 5 -OutputPrefix .\s0-1
```

Repeat with the same machine, DPI, data and settle time for S0, S1, S2 and S3 (1, 2, 5 and 10 windows total), three independent iterations. Record content, launch time and close/reopen phases; preserve per-process and summary CSV. The sampler observes the live parent tree and flags unavailable processes; detached/reparented WebView2 children are not included. Its initial system-wide process map contains only process IDs, parent IDs, names and creation times. It does not inspect messages or command lines. Empty WebView value means no attributed process, not a proven zero. GPU and Dart heap are unavailable in this script. Working sets can include shared pages and must not be added to private commit.

| Scenario | Private MiB median | Working set MiB median | Result |
|---|---:|---:|---|
| S0 main | 328.01 | 201.32 | one run, median of three samples; not a three-run median |
| S1 +1 chat | — | — | not measured |
| S2 +4 chat | — | — | not measured |
| S3 +9 chat | — | — | not measured |
| profile, browser, media and 30 close/reopen cycles | — | — | not measured |

The actual sample is in `windows-baseline-s0-summary.csv` and `windows-baseline-s0-processes.csv`; root PID 39500, one attributed process. No WebView2 descendant was attributed at sampling time; that is not proof of zero WebView memory. The process tree may omit detached processes. Do not calculate savings, per-window averages or leak conclusions until matched measurements exist. The test account, display/DPI, GPU, device memory and actual hidden and visible window counts must be recorded for a full baseline.

## Existing user window state (2026-11-03)

The same Release root was sampled after the user opened their usual windows. The visible and hidden window counts and content were not enumerated, so this is **not** S1/S2/S3 and is not comparable to a controlled experiment. Three samples give median process-tree private commit 2,070.76 MiB and summed working set 1,580.39 MiB, including six attributed WebView2 descendants with median private commit 197.81 MiB. The root process private commit at the first sample was 1,871.95 MiB. A summed working set includes shared pages and can double-count them; it must not be added to private commit. Attribution is limited to the observed parent tree. See `windows-existing-windows-processes.csv` and `windows-existing-windows-summary.csv`.
