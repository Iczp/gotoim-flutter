# 统一单元格组件：CellGroup 与 Cell

`CellGroup` 与 `Cell` 是 GotoIM 客户端中用于构建**个人资料、账号中心、应用设置、列表菜单**等页面的统一 UI 基础组件。

通过将零散的 `_SectionHeader`、`GlassCard`、`ListTile` 和手动 `Divider` 进行体系化封装，既保留了原 UniApp 项目中 `CellGroup / Cell` 的声明式 API 习惯，又在 Flutter 端提供了沉浸式毛玻璃质感与高性能水波纹交互。

---

## 一、设计背景与核心原则

1. **视觉统一**：
   - 分组标题样式严格遵循 `MinePage` 的 `_SectionHeader` 规范（主色调高亮、加粗、标准内边距）；
   - 卡片背景默认采用 `GlassCard`，具备高斯模糊、反光边框与柔和投影，完美适配动态主题与深浅色模式。
2. **高保真点击反馈**：
   - `Cell` 内部采用透明 `Material` + `InkWell` 绘制，解决了原生 `ListTile` 被外层 `DecoratedBox` 遮挡导致的水波纹/点击高光不可见问题。
3. **两端对齐布局 (`justify-between`)**：
   - 标题与图标居左自然排列，右侧的内容文本（`value`）、自定义组件（`valueWidget`）与右箭头（`showArrow`）整体扩展并紧贴最右端，实现标准的两端对齐。
4. **零模板代码**：
   - `CellGroup` 会自动在 `children` 相邻项之间插入缩进的分隔线 `Divider`，业务开发无需在列表项之间手动拼接分割线。
5. **复合扩展性**：
   - 除了支持 `children: [Cell(...), ...]` 列表项模式，还支持 `child: ...` 单一自定义组件模式（例如混排 `SegmentedButton`、`SwitchListTile` 或滑动开关）。

---

## 二、架构与组件层次

```text
ListView
 └── CellGroup (分组卡片容器)
      ├── Header (标题：主色高亮加粗)
      └── GlassCard (毛玻璃圆角卡片)
           └── Column (垂直排列 + 自动插入 Divider)
                ├── Cell (项 1：图标 + 标题 + 副标题 + 文本值 + 右箭头)
                ├── Divider (自动添加)
                ├── Cell (项 2：支持点击一键复制)
                ├── Divider (自动添加)
                └── Cell (项 3：自定义组件/标红退出)
```

---

## 三、API 详细说明

### 1. `CellGroup` 参数列表

| 参数 | 类型 | 默认值 | 说明 |
| :--- | :--- | :--- | :--- |
| `title` | `String?` | `null` | 分组头部标题文本，渲染为高亮加粗标签 |
| `titleWidget` | `Widget?` | `null` | 自定义头部组件，存在时优先于 `title` |
| `children` | `List<Widget>?` | `null` | 单元格项列表（相邻项自动添加分隔线） |
| `child` | `Widget?` | `null` | 自定义内容组件（与 `children` 二选一，用于复杂自定义排版） |
| `margin` | `EdgeInsetsGeometry` | `EdgeInsets.only(bottom: 12)` | 分组卡片的外边距 |
| `padding` | `EdgeInsetsGeometry` | `EdgeInsets.zero` | 卡片内部的内边距 |
| `borderRadius` | `BorderRadiusGeometry?` | `BorderRadius.circular(16)` | 卡片圆角 |
| `useGlass` | `bool` | `true` | 是否应用毛玻璃效果（设为 `false` 时使用纯色 Material 材质） |
| `backgroundColor`| `Color?` | `null` | 覆盖卡片背景色 |
| `borderColor` | `Color?` | `null` | 覆盖卡片边框颜色 |
| `dividerIndent` | `double` | `16.0` | 自动插入分隔线的左侧缩进距离 |
| `subTitleColor` / `subtitleColor` | `Color?` | `null` | 分组级别副标题颜色（向下级所有 Cell 统一透传） |
| `arrowColor` | `Color?` | `null` | 分组级别箭头颜色（向下级所有 Cell 统一透传） |

### 2. `Cell` 参数列表

| 参数 | 类型 | 默认值 | 说明 |
| :--- | :--- | :--- | :--- |
| `title` | `String` | **必填** | 单元格主标题文本 |
| `value` | `String?` | `null` | 右侧展示的文本内容（自动单行截断省略） |
| `valueWidget` | `Widget?` | `null` | 右侧自定义组件（徽标、胶囊标签等） |
| `subtitle` | `String?` | `null` | 标题下方的辅助副标题文本 |
| `subtitleWidget`| `Widget?` | `null` | 自定义副标题组件 |
| `icon` | `Widget?` | `null` | 左侧图标或前缀组件 |
| `trailing` | `Widget?` | `null` | 自定义尾部组件（存在时替换 `value`、`valueWidget` 和 `showArrow`） |
| `showArrow` | `bool` | `false` | 是否在右侧展示导航右箭头 (`Icons.chevron_right`) |
| `canCopy` | `bool` | `false` | 点击时是否将值复制到系统剪贴板并弹出 Toast 提示 |
| `copyValue` | `String?` | `null` | 复制的内容（缺省时自动使用 `value` 或 `title`） |
| `onTap` | `VoidCallback?` | `null` | 点击回调事件（优先级高于 `canCopy`） |
| `switchValue` | `bool?` | `null` | 开关状态值（若提供，右侧自动渲染 Switch 并与整行点击联动） |
| `onSwitchChanged`| `ValueChanged<bool>?`| `null` | 开关状态变化回调事件 |
| `titleColor` | `Color?` | `null` | 主标题颜色（可用于“退出登录”等危险操作标红） |
| `subTitleColor` / `subtitleColor` | `Color?` | `onSurfaceVariant(0.5)` | 副标题文本颜色（默认透明度 0.5） |
| `arrowColor` | `Color?` | `onSurfaceVariant(0.5)` | 右侧箭头指示器颜色（默认透明度 0.5） |
| `isCentered` | `bool` | `false` | 标题是否居中显示（适用于“退出登录”、“清空数据”等按钮项） |
| `disabled` | `bool` | `false` | 是否禁用置灰与点击响应 |
| `padding` | `EdgeInsetsGeometry` | `EdgeInsets.symmetric(horizontal: 16, vertical: 14)` | 单元格内边距 |

---

## 四、使用示例

### 示例 1：基础导航列表项 (类似“我的内容”)

```dart
CellGroup(
  title: '我的内容',
  children: [
    Cell(
      icon: const Icon(Icons.manage_accounts_outlined),
      title: '账号设置',
      showArrow: true,
      onTap: () => context.push('/account/profile'),
    ),
    Cell(
      icon: const Icon(Icons.qr_code_scanner_rounded),
      title: '扫一扫',
      showArrow: true,
      onTap: () => scanDispatcher.openAndDispatch(context, ref),
    ),
    Cell(
      icon: const Icon(Icons.bookmark_outline_rounded),
      title: '我收藏的',
      showArrow: true,
      onTap: () => showToast('收藏夹暂无内容', type: ToastType.info),
    ),
  ],
)
```

---

### 示例 2：信息展示与一键复制 (类似“账号基本信息”)

无需编写剪贴板与 Toast 代码，声明 `canCopy: true` 即可：

```dart
CellGroup(
  children: [
    Cell(
      title: '账号',
      value: 'admin@gotoim.com',
      canCopy: true,
    ),
    Cell(
      title: '名称',
      value: '系统管理员',
      canCopy: true,
    ),
    Cell(
      title: '设备ID',
      value: deviceId.length > 16 ? '${deviceId.substring(0, 16)}...' : deviceId,
      canCopy: true,
      copyValue: deviceId, // 复制完整的完整设备 ID
    ),
  ],
)
```

---

### 示例 3：副标题与自定义右侧组件 (类似“设备信息与授权”)

```dart
CellGroup(
  title: '设备与安全',
  children: [
    Cell(
      icon: const Icon(Icons.devices_rounded),
      title: '设备信息',
      subtitle: '当前已登录 3 台终端设备',
      showArrow: true,
      onTap: () => context.push('/devices'),
    ),
    Cell(
      title: '安全授权',
      showArrow: true,
      valueWidget: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('0', style: TextStyle(fontSize: 12)),
      ),
      onTap: () => context.push('/authorizations'),
    ),
  ],
)
```

---

### 示例 4：居中危险操作项 (类似“退出登录”)

```dart
CellGroup(
  margin: const EdgeInsets.only(bottom: 24),
  children: [
    Cell(
      title: '退出登录',
      titleColor: Colors.red,
      isCentered: true,
      onTap: () async {
        final confirmed = await showConfirmModal(
          context: context,
          title: '退出登录',
          message: '确定要退出当前账号登录吗？',
          confirmText: '退出',
          isDestructive: true,
        );
        if (confirmed) {
          await authController.logout();
        }
      },
    ),
  ],
)
```

---

### 示例 5：自定义复合控件排版 (`child` 模式)

当卡片内不是普通的单元格，而是包含复杂表单或控制器时，可以使用 `child` 模式：

```dart
CellGroup(
  title: '外观与主题',
  padding: const EdgeInsets.all(12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('主题模式', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
          ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
          ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
        ],
        selected: {themeMode},
        onSelectionChanged: (set) => setMode(set.first),
      ),
    ],
  ),
)
```

---

### 示例 6：开关配置项 (`switchValue` 模式)

支持直接将单元格变为开关项，点击整行或开关均可自动触发切换，副标题自动应用统一的 0.5 透明度：

```dart
CellGroup(
  title: '功能开关',
  children: [
    Cell(
      icon: const Icon(Icons.blur_on_rounded),
      title: '底部导航毛玻璃效果',
      subtitle: '开启后导航栏具有高斯模糊与半透明质感',
      switchValue: ref.watch(tabGlassProvider),
      onSwitchChanged: (val) {
        ref.read(tabGlassProvider.notifier).setEnabled(val);
      },
    ),
  ],
)
```

---

## 五、最佳实践与排坑指南

1. **避免手动添加 Divider**：
   - `CellGroup` 内部已经自动处理了相邻元素之间的分隔线与缩进，直接按顺序传入 `children` 即可。
2. **避免重复外层 SizedBox**：
   - `CellGroup` 的 `margin` 默认已包含 `EdgeInsets.only(bottom: 12)`，分组与分组之间无需额外插入 `SizedBox(height: 12)`。
3. **避免嵌套滚动**：
   - `CellGroup` 内部使用轻量的 `Column` 线性排列，不会创建多余的滚动视口，直接放入页面的外层 `ListView` 中性能最佳。
4. **材质适配**：
   - 在不支持毛玻璃或特定低性能环境中，可传入 `useGlass: false`，组件将平滑回退为实体 Surface 材质，但外观阴影与圆角比例保持一致。
