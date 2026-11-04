# Windows Multi-Window Optimization Changelog

**Date**: 2026-11-03  
**Branch**: `dev`  

---

## 1. 修改文件清单

### 核心应用代码修改
1. **`lib/core/services/window_service.dart`**:
   - 将 `_maxReusableControllers` 默认上限从 `6` 压缩为 `1`。
   - 增加**通用聊天子窗口复用逻辑 (Generic Chat SubWindow Reuse)**：在 `_openNativeSubWindow` 中，当请求打开任意聊天窗口且无对应会话缓存时，自动提取 `_reusableControllers` 中现存的任一闲置聊天引擎进行复用，不再强制创建新引擎。
   - 修复托盘 Flyout 窗口唤起与 `_waitWindowReady` 准备逻辑。
2. **`lib/core/native_window/native_sub_window_app.dart`**:
   - 在接收到 `window_release_content` IPC 消息时，将事件转发给活跃的子视图处理器 `_childMethodHandler`。
   - 显式触发 `PaintingBinding.instance.imageCache.clear()` 与 `clearLiveImages()`，在窗口关闭/隐藏时将已解码的高分辨率图片 Bitmap 立即从内存中抹除。
3. **`lib/core/native_window/desktop_sub_window_chat_view.dart`**:
   - 增加对 `window_release_content` 的处理，在窗口关闭时清空 `_messages`、`_attachments`、`_inputController`，并重置加载状态。
   - 抽取 `_createChatController` 方法，并在 `didUpdateWidget` 中检测会话 `sessionUnitId` 或 `ownerId` 的变更：当控制器被不同会话复用时，安全销毁旧控制器并重建新控制器，清空历史消息防止串号混杂。
   - 在 `_loadHistory` 中，当非向上翻页 (`!older`) 时，以全新消息列表覆盖旧消息，杜绝多次切换会话后的无界内存累加。

### 新增原型与文档
1. **`examples/desktop_multiview_poc/`**:
   - 单 Engine 多 FlutterView 独立验证原型（包含独立 `pubspec.yaml`, `windows/runner`, `lib/main.dart`）。
   - 包含多窗口状态共享、动态窗口生成、中文输入与 1/5/10 窗口自动测试开关。
2. **`docs/performance/`**:
   - `WINDOWS-MULTIWINDOW-AUDIT.md`: 现有架构与内存根因深度审计。
   - `WINDOWS-MEMORY-BASELINE.md`: 原始、优化版与 PoC 性能采样数据与实测矩阵。
   - `WINDOWS-MULTIVIEW-FEASIBILITY.md`: 插件兼容性矩阵与 Win32 原生集成评估。
   - `WINDOWS-MULTIWINDOW-ACCEPTANCE.md`: 验收门禁核对与决策报告。
   - `WINDOWS-MULTIWINDOW-CHANGELOG.md`: 本变更记录。
   - 实测 CSV 数据文件 (`windows-multiview-poc-s0-*`, `windows-multiview-poc-s2-*`, `windows-multiview-poc-s3-*`, `windows-optimized-s0-*`)。

---

## 2. 回滚方式 (Rollback Instructions)

如需回滚本次旧架构优化：
```bash
git checkout HEAD -- lib/core/services/window_service.dart lib/core/native_window/native_sub_window_app.dart lib/core/native_window/desktop_sub_window_chat_view.dart
```
