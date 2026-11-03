# Changes and rollback

- Added `scripts/perf/windows-memory-sample.ps1` for repeatable, non-destructive process-tree samples. Delete its outputs after local use as appropriate; the script does not terminate processes or clear caches.
- Added audit, baseline, feasibility and acceptance documents. No production window backend was replaced in this change. Revert the corresponding commit to remove the sampler and reports.
