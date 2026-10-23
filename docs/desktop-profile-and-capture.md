# Windows 悬浮资料卡与截图交互

资料卡保持独立的常驻窗口，不接入聊天右侧吸附槽。`WindowService.showProfileCardAt` 将头像逻辑坐标转换为屏幕物理坐标，原生 `positionFlyout` 根据头像所在显示器的 DPI 和 `rcWork`（排除任务栏）计算卡片位置，右侧空间不足时翻到左侧，再约束到可用区域。支持负坐标显示器；不按主窗口边界裁剪。

原生窗口每 50ms 检查鼠标是否在头像或卡片内，连续离开 450ms 后隐藏。点击激活卡片后，卡片及其拥有的对话框保持可操作，切换到其他窗口时隐藏。旧的头像离开定时器和卡片 `MouseRegion.onExit` 定时器已移除，避免鼠标已移入卡片却被旧任务关闭。关闭、Escape、发消息和诊断页主动隐藏仍立即生效；窗口隐藏或释放时停止原生计时器。

截图工作台统一以 `LayoutBuilder` 提供的逻辑画布尺寸处理鼠标与选区。物理截图尺寸仅用于底图和导出换算，导出保持原始像素分辨率。输入直接由画布的指针事件处理，避免手势起点阈值和双击识别影响拖动；工具栏独立命中，不会触发移动选区。

底图位于独立的 `RepaintBoundary` 内，动态层只绘制遮罩、选框和标注。遮罩通过 even-odd 路径绘制，避免每次指针移动都分配全屏 `saveLayer`。每次复用会释放旧截图、解码器和导出图片资源。

验证入口：桌面窗口诊断页的资料卡预热/显示/隐藏及截图测试。原生窗口诊断额外返回 `profileHoverTracking`、`profileAnchor`、`monitorWorkArea`。

自动化验证：

```powershell
flutter test test/desktop/screen_capture_interaction_test.dart
cmake -S test/desktop/native -B build/profile-flyout-policy
cmake --build build/profile-flyout-policy --config Debug
./build/profile-flyout-policy/Debug/profile_flyout_policy_test.exe
```

Flutter 测试覆盖 100%、150%、200% 缩放的精确起点、框选、移动边界、锚点缩放、工具栏命中和导出像素尺寸；原生策略测试覆盖左右翻转、负坐标、工作区边界、超大卡片、跨窗口悬停宽限、重新进入和交互保留。不同 DPI 的真实多显示器组合及交互帧率仍需在目标机器验收。
