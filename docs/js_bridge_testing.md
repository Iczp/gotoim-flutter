# JS Bridge 测试方法

## 当前工程内测试

1. 以 Debug 启动 Flutter 应用，进入“开发诊断中心 → JS Bridge 测试”。
2. 点击“系统信息”“网络类型”“能力清单”等预设，确认响应具有相同的 `id` 与 `success:true`。
3. 发送以下订阅请求，记录响应中的 `subscriptionId`：

```json
{"id":"network-1","action":"onNetworkStatusChange","data":{"subscriptionId":"network-test"}}
```

4. 切换 Wi‑Fi/移动网络，确认“异步事件”收到 `network.statusChange`。随后必须发送：

```json
{"id":"network-off","action":"offNetworkStatusChange","data":{"subscriptionId":"network-test"}}
```

5. “JS Bridge 测试 → 文件上传任务测试”的地址直接读取环境变量 `JS_BRIDGE_UPLOAD_URL`（开发默认 `http://10.0.5.20:4173/upload`）。依次点击“选择文件 → 订阅上传事件 → 开始上传”，确认“响应”含 `taskId`，而“异步事件”依次出现 `file.uploadQueued`、`file.uploadProgress` 和 `file.uploadCompleted`。可用“取消任务”和“取消上传订阅”验证清理路径；两个 JSON 面板均可直接复制。
6. 在“媒体与文件测试”选择一张二维码图片，确认“图片识码”显示 `content`、`format` 和 `source`；再测试拍照、录像、录音、另存为。移动设备上必须接受相机、相册、麦克风授权。

自动化层已覆盖 JSON 请求/响应、未知 action、网络订阅事件和 `JsBridgeSession` transport 转发；实际相机/麦克风/系统文件对话框需在真机手工验证。

## 独立 Web 测试站

已创建独立、无业务鉴权的静态 H5 harness：`F:\Dev\GotoIM\gotoim-flutter-jsbridge`。原因是普通 Flutter Web 没有 WebView JavaScriptChannel，无法端到端验证“网页 → 宿主 → 网页”链路；必须将该站点装载在 Flutter 的原生 WebView 中。

站点包含：

- `index.html`：action 下拉、JSON 编辑器、请求/响应/事件面板；
- `bridge-client.js`：以 `id` 匹配 Promise、监听 `network.statusChange`、支持取消订阅；
- `fixtures/`：小于 10 MiB 的二维码图片和媒体样本；
- 无 Token、无私有 API、无真实用户数据。

启动方法：

```powershell
cd F:\Dev\GotoIM\gotoim-flutter-jsbridge
python server.py --bind 0.0.0.0 --port 4173
```

在 Flutter Debug 应用中进入“开发诊断中心 → JS Bridge Harness”。默认地址读取当前环境文件的 `JS_BRIDGE_HARNESS_URL`；开发环境已配置为 `http://10.0.5.20:4173`。未配置时，Android 回退为 `http://10.0.2.2:4173`（模拟器），iOS/macOS 回退为 `http://127.0.0.1:4173`。真机须使用电脑的局域网 IP。

Harness 会显示请求进度、完成地址和明确的网络/WebView 错误；15 秒没有完成会报告超时，错误文字可选中或点复制按钮直接复制。Android 主 Manifest 已声明 `INTERNET` 并允许明文 HTTP，因此所有 Android 构建变体均可访问局域网 `http://` 服务；Harness 页面本身仍只在 Debug 模式暴露。

Harness 支持 Android、iOS、macOS 与 Windows。Windows 使用 WebView2：需要 Windows 10 1809+ 和 WebView2 Runtime；若运行时缺失，页面会显示初始化错误。Web 与 Linux 继续使用 JSON 模拟诊断页。

### 上传闭环验证

1. 确认 `.env.development` 中 `JS_BRIDGE_UPLOAD_URL="http://10.0.5.20:4173/upload"`，且 `JS_BRIDGE_UPLOAD_ALLOWED_HOSTS` 包含测试站点主机（默认含 `10.0.5.20`），完整重启 Flutter。Harness 会将这个地址主动下发给 H5，页面内不可编辑。
2. 在 Harness 的“宿主代理上传”选择一个非敏感测试文件，点击“订阅上传事件”，再点击“开始上传”。确认进度条与百分比增长，并最终出现 `file.uploadCompleted` 和 `receivedBytes`。`server.py` 只读取并丢弃字节，不落盘。
3. 在“H5 原生文件上传”中点击原生文件控件，确认 Android/iOS/Windows 弹出系统文件选择器；选择文件后点击“上传所选文件”。确认第二条进度条增长、最终响应含 `receivedBytes`。这条链路使用 H5 `File` + `XMLHttpRequest`，不经过 `fileId` 或 Bridge 上传任务。
4. 选择较大测试文件后，再分别取消两种上传：代理上传点击“取消任务”，网页上传点击“取消网页上传”。代理方式应出现 `file.uploadCancelled`；网页方式显示“已取消网页上传”。离开页面前点击“取消上传订阅”。
5. 点击 Flutter 页面的“Flutter → H5 Ping”。按钮下方的“Flutter → H5 Ping 回执”先显示 `pingId` 和“等待 H5 回执”，随后必须显示 `diagnostics.hostPingResult` JSON。确认 `success:true`、`pingId` 一致且 `systemInfo` 非空；该回执可直接复制。未出现回执即代表主动事件、H5 回调或 Bridge 返回其中一段未完成。这验证 Flutter 主动调用 WebView、网页主动回调 Flutter、以及 JSON 响应三段链路。

当前开发机的默认 `cmake` 若低于 3.20，无法构建 Windows WebView2 插件。Visual Studio 已安装新版 CMake 时，可在启动前执行：

```powershell
$env:Path = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;' + $env:Path
flutter run -d windows
```

最小验证矩阵：Android 真机（相机、录像、录音、视频压缩）、iPhone/iPad（权限与相册）、Windows（文件路径/另存为/录音）、WebView 中的 H5（所有 JSON action、取消订阅和文件引用失效）。在生产接入实际 WebView 插件之前，先用该 harness 固化协议回归测试最合适。
