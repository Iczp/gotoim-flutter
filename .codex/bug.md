# Bug汇总



进聊天窗口

```
/api/chat/message/latest?sessionUnitId=cbcd06cf-2be4-473a-7270-3a09b882f73f&maxResultCount=99&minMessageId=7297401
```

加载了12条消息，是要写入数据库的 -- 请检查

重新再进 参数minMessageId 还是 7297401 是不对的。
加载了新消息，minMessageId 应该是要比 7297401  大



这是两个进入相关会话  /api/chat/message/latest 都反回了30条，理论上第一次返回30条，进入数据库，第二次应该是要 更新 获取本地的最大MessageId 传到  接口的 minMessageId 

MethodAddressStatusTypeDurationSizeTimestampSOCKET10.0.5.20:8044Closedtcp4 s58.1 kB13:53:40.200SOCKET10.0.5.20:8044Closedtcp3 s2.6 kB13:53:40.375GEThttp://10.0.5.20:8044/api/chat/session-unit-cache/friend/221a1d41-2c74-c701-b407-3a0b0cf4331e200json111 ms-13:53:40.636GEThttp://10.0.5.20:8044/api/chat/message/latest?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&maxResultCount=99&minMessageId=7297037200json80 ms-13:53:40.751POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297037200json184 ms-13:53:40.806POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297320200json120 ms-13:53:41.106SOCKET10.0.5.20:8044Closedtcp3 s3.5 kB13:54:07.931SOCKET10.0.5.20:8044Closedtcp4 s57.2 kB13:54:07.964GEThttp://10.0.5.20:8044/api/chat/session-unit-cache/friend/221a1d41-2c74-c701-b407-3a0b0cf4331e200json148 ms-13:54:08.284GEThttp://10.0.5.20:8044/api/chat/message/latest?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&maxResultCount=99&minMessageId=7297037200json98 ms-13:54:08.398POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297037200json130 ms-13:54:08.513POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297320200json164 ms-13:54:08.811

### 进聊天窗口\

friend detai   中没有lastMessage,  因此，要先读取本地的friend  lastMessage, 再合并。   

showToast 选项增加是否振动，是否发出声音，全已局位置配置， 



### Modal

```
lib\features\diagnostics\presentation\modal_diagnostics_page.dart
 The overflowing RenderFlex has an orientation of Axis.horizontal.
The edge of the RenderFlex that is overflowing has been marked in the rendering with a yellow and
black striped pattern. This is usually caused by the contents being too big for the RenderFlex.
Consider applying a flex factor (e.g. using an Expanded widget) to force the children of the
RenderFlex to fit within the available space instead of being sized to their natural size.
This is considered an error condition because it indicates that there is content that cannot be
seen. If the content is legitimately bigger than the available space, consider clipping it with a
ClipRect widget before putting it in the flex, or using a scrollable container rather than a Flex,
like a ListView.
The specific RenderFlex in question is: RenderFlex#c9a6e relayoutBoundary=up14 OVERFLOWING:
  creator: Row ← Padding ← Column ← Semantics ← DefaultTextStyle ← AnimatedDefaultTextStyle ←
    _InkFeatures-[GlobalKey#b649a ink renderer] ← NotificationListener<LayoutChangedNotification> ←
    CustomPaint ← _ShapeBorderPaint ← PhysicalShape ← _MaterialInterior ← ⋯
  parentData: offset=Offset(16.0, 8.0) (can use size)
  constraints: BoxConstraints(0.0<=w<=296.0, 0.0<=h<=Infinity)
  size: Size(296.0, 24.0)
  direction: horizontal
  mainAxisAlignment: start
  mainAxisSize: max
  crossAxisAlignment: center
  textDirection: ltr
  verticalDirection: down
  spacing: 0.0
◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤
════════════════════════════════════════════════════════════════════════════════════════════════════

I/flutter (26013): Flutter error: A RenderFlex overflowed by 20 pixels on the right.
I/flutter (26013): null
```



```
I/flutter (26013): Flutter error: Build scheduled during frame.
I/flutter (26013): While the widget tree was being built, laid out, and painted, a new frame was scheduled to rebuild the widget tree.
I/flutter (26013): This might be because setState() was called from a layout or paint callback. If a change is needed to the widget tree, it should be applied as the tree is being built. Scheduling a change for the subsequent frame instead results in an interface that lags behind by one frame. If this was done to make your build dependent on a size measured at layout time, consider using a LayoutBuilder, CustomSingleChildLayout, or CustomMultiChildLayout. If, on the other hand, the one frame delay is the desired effect, for example because this is an animation, consider scheduling the frame in a post-frame callback using SchedulerBinding.addPostFrameCallback or using an AnimationController to trigger the animation.
I/flutter (26013): #0      WidgetsBinding._handleBuildScheduled.<anonymous closure> (package:flutter/src/widgets/binding.dart:1435:9)
I/flutter (26013): #1      WidgetsBinding._handleBuildScheduled (package:flutter/src/widgets/binding.dart:1458:6)
I/flutter (26013): #2      BuildOwner.scheduleBuildFor (package:flutter/src/widgets/framework.dart:3000:24)
I/flutter (26013): #3      Element.markNeedsBuild (package:flutter/src/widgets/framework.dart:5403:12)
I/flutter (26013): #4      ConsumerStatefulElement.watch.<anonymous closure>.<anonymous closure> (package:flutter_riverpod/src/core/consumer.dart:492:27)
I/flutter (26013): #5      InternalProviderContainer.runBinaryGuarded (package:riverpod/src/core/provider_container.dart:811:9)
I/flutter (26013): #6      ProviderSubscriptionImpl._notifyData (package:riverpod/src/core/provider_subscription.dart:203:32)
I/flutter (26013): #7      InternalProviderContainer.runBinaryGuarded (package:riverpod/src/core/provider_container.dart:811:9)
I/flutter (26013): #8      ProviderElement._notifyListeners (package:riverpod/src/core/element.dart:910:21)
I/flutter (26013): #9      Ref.notifyListeners (package:riverpod/src/core/ref.dart:422:16)
I/flutter (26013): #10     _ChangeNotifierProviderElement.create.listener (package:flutter_riverpod/src/providers/legacy/change_notifier_provider.dart:231:30)
I/flutter (26013): #11     ChangeNotifier.notifyListeners (package:flutter/src/foundation/change_notifier.dart:435:24)
I/flutter (26013): #12     SessionListController.loadNextPage (package:gotoim_flutter/features/session/application/session_list_controller.dart:287:5)
I/flutter (26013): #13     _SessionListPageState.build.<anonymous closure> (package:gotoim_flutter/features/session/presentation/session_list_page.dart:74:32)
I/flutter (26013): #14     _NotificationElement.onNotification (package:flutter/src/widgets/notification_listener.dart:135:38)
I/flutter (26013): #15     _NotificationNode.dispatchNotification (package:flutter/src/widgets/framework.dart:3508:18)
I/flutter (26013): #16     _NotificationNode.dispatchNotification (package:flutter/src/widgets/framework.dart:3511:13)
I/flutter (26013): #17     Element.dispatchNotification (package:flutter/src/widgets/framework.dart:5265:24)
I/flutter (26013): #18     Notification.dispatch (package:flutter/src/widgets/notification_listener.dart:68:13)
I/flutter (26013): #19     ScrollActivity.dispatchScrollStartNotification (package:flutter/src/widgets/scroll_activity.dart:100:65)
I/flutter (26013): #20     ScrollPosition.didStartScroll (package:flutter/src/widgets/scroll_position.dart:1043:15)
I/flutter (26013): #21     ScrollPosition.beginActivity (package:flutter/src/widgets/scroll_position.dart:1035:7)
I/flutter (26013): #22     ScrollPositionWithSingleContext.beginActivity (package:flutter/src/widgets/scroll_position_with_single_context.dart:120:11)
I/flutter (26013): #23     ScrollPositionWithSingleContext.goBallistic (package:flutter/src/widgets/scroll_position_with_single_context.dart:153:7)
I/flutter (26013): #24     IdleScrollActivity.applyNewDimensions (package:flutter/src/widgets/scroll_activity.dart:187:14)
I/flutter (26013): #25     ScrollPosition.applyNewDimensions (package:flutter/src/widgets/scroll_position.dart:736:15)
I/flutter (26013): #26     ScrollPositionWithSingleContext.applyNewDimensions (package:flutter/src/widgets/scroll_position_with_single_context.dart:109:11)
I/flutter (26013): #27     ScrollPosition.applyContentDimensions (package:flutter/src/widgets/scroll_position.dart:662:7)
I/flutter (26013): #28     RenderViewport.performLayout (package:flutter/src/rendering/viewport.dart:1732:20)
I/flutter (26013): #29     RenderObject._layoutWithoutResize (package:flutter/src/rendering/object.dart:2771:7)
I/flutter (26013): #30     PipelineOwner.flushLayout (package:flutter/src/rendering/object.dart:1174:18)
I/flutter (26013): #31     PipelineOwner.flushLayout (package:flutter/src/rendering/object.dart:1187:15)
I/flutter (26013): #32     RendererBinding.drawFrame (package:flutter/src/rendering/binding.dart:692:23)
I/flutter (26013): #33     WidgetsBinding.drawFrame (package:flutter/src/widgets/binding.dart:1573:13)
I/flutter (26013): #34     RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:558:5)
I/flutter (26013): #35     SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
I/flutter (26013): #36     SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
I/flutter (26013): #37     SchedulerBinding._handleDrawFrame (package:flutter/src/scheduler/binding.dart:1198:5)
I/flutter (26013): #38     _invoke (dart:ui/hooks.dart:441:13)
I/flutter (26013): #39     PlatformDispatcher._drawFrame (dart:ui/platform_dispatcher.dart:450:5)
I/flutter (26013): #40     _drawFrame (dart:ui/hooks.dart:413:31)
```



```
进入聊天窗口有点卡 返回时，V/InputMethodManager(10385): dispatchInputEvent
V/InputMethodManager(10385): dispatchInputEvent
I/AudioManager(10385): abandonAudioFocusRequest focusRequest
I/InputTransport(10385): Fun_filterMotionEvent reportMoveEvent!

进入聊天窗口 都做了哪个， 列出来一下。
```



消息菜单

是按消息内容，文本语音图片等， 不包含头像时间，
同时还 多选  一行四个，多了要分两行，再多就有 “更多”图标

菜单排版（支持单行和双行，默认双行）， 
图标   （换行）
文字

聊天窗口   头像 菜单  竖排（图标 -文字(底部有分隔线，) ）

- @TA
- 特别关注
- 取消关注
- 禁言

## 待修改

### 视频预览

1. 小窗口按钮 和 播放控制 要浮动 透明度 0.8，滑动关闭要与 关闭按钮一样，透明度减小
2. 图片和视频预览 最底部右下角  有下载、分享  

### 扫码统一入口，不再分二维码和登录码

同时也要更新JSbridge

### 登录设备

账号管理

### 我的


_ProfileSettingsPage  独立出页，  mine

- 我收藏的
- 我关注的
- 

- 设置 

  - 账号管理

  - 设备信息



退出需要二次确认（统一使用 showModal），调用Auth的退出，让Token在服务器立即失效



### 聊天设置

- 设置聊天背景
- 清空消息要二次确认（统一使用 showModal）

修改群名称 

修改会话内名称

### Tab 毛玻璃效果，

开关是否使用毛玻璃。配置在 设置  里



### 探索

- 文件管理（局域网）
- 开发日志

### 工作台

设计参数（名称，打开方式）

### 消息

#### 本文本消息

解析，

### 聊天输入框

- 功能区
- 键盘区
- 公众号菜单

