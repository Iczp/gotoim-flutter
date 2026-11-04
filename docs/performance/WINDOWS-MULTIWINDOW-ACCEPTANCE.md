# Windows Multi-Window Acceptance & Verification Report

**Date**: 2026-11-03  
**Status**: **ACCEPTED FOR PRODUCTION STABILIZATION (Candidate C: Optimized Multi-Engine Architecture)**  
**Branch**: `dev`  
**Test Suite**: 19/19 Unit & Desktop Regression Tests Passed (100%)  

---

## 1. 验收清单核对 (Checklist)

- [x] **Windows Release 构建**: `flutter build windows --release` 成功构建无报错。
- [x] **回归测试**: `flutter test test/core/services/window_service_test.dart test/desktop/windows_repair_regression_test.dart test/desktop/desktop_chat_reuse_test.dart` 全部 19 项通过。
- [x] **主窗口启动与托盘恢复**: 主窗口冷启动、热启动与托盘交互正常。
- [x] **防止重复窗口创建**: `WindowService.isWindowOpen` 与原子化占位防止同一会话重复弹窗。
- [x] **通用聊天窗口复用**: 闲置聊天引擎不再绑定具体 `sessionId`，打开任意新聊天即可秒级复用，消除多余引擎创建。
- [x] **引擎缓存上限压缩**: `_maxReusableControllers` 从 6 降为 1，多余闲置引擎即时调用 Win32 原生 `destroy` 彻底销毁。
- [x] **子窗口资源与图片缓存清理**: 窗口关闭时显式清空 `_messages`、`_attachments`，并触发 `PaintingBinding.instance.imageCache.clear()`。
- [x] **跨平台安全性**: Android, iOS, Web, macOS, Linux 入口与代码未受任何破坏。
- [x] **单 Engine 多 View 独立原型**: 在 `examples/desktop_multiview_poc/` 独立验证完成，10 窗口实测仅 **515.65 MB**。
- [x] **兼容性与阻断项记录**: 明确记录 `window_controls.cpp` 原生分屏 Docking 与 `flutter_inappwebview` 对全量 MultiView 迁移的阻断原因。

---

## 2. 最终性能对比总结

```text
原始用户多开状态: 1,871.95 MB (6+ 引擎后台积压)
   ↓ (优化引擎缓存上限为 1 + 通用复用 + 内容主动释放)
优化后旧架构稳定版: 闲置引擎销毁，多开聊天秒级复用已有引擎，消除 ~750MB~900MB 冗余内存！
   ↓ (单 Engine 多 View 原型测定)
单 Engine PoC 10 窗实测: 515.65 MB (平均每窗增量降至 37.88 MB，较原始节省 72.45%)
```
