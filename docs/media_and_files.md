# 媒体、文件与录音能力

实现位于 `lib/core/services/file/`、`lib/core/services/media/`，应用入口为 `ClientCapabilityService`。诊断入口：Debug 模式的“开发诊断中心 → 媒体与文件测试”。所有返回会显示文件 `fileId`、大小、URI、原始路径（若平台允许）。

## 文件生命周期

`SelectedFile` 是当前应用会话可用的文件引用：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `fileId` | string | 会话内唯一标识，供 JS Bridge 后续 API 使用；重启/清理后失效 |
| `name` / `size` / `extension` / `mimeType` | string / number | 文件元数据；无法推断的 MIME 为 `null` |
| `uri` | string | 选择器提供的原始 URI；可能是 `file:`、`content:`、`blob:` 等 |
| `path` | string? | 原始本机路径；SAF/Web 不保证存在，不能假设必有 |
| `hasNativePath` | boolean | 是否可安全交给仅接受本机路径的视频处理器 |

直接 Dart 调用可使用 `readBytes()` / `readAsByteStream()` 上传。Bridge 的 `file.readFile` 只允许当前会话的 `fileId`，且响应上限为 10 MiB；大文件必须走 HTTP 分片上传接口。

### `chooseFile(request)`

参数：`allowMultiple=false`、`allowedExtensions=[]`、`dialogTitle?`。用户取消时返回空数组。

### `saveFile(request)`

`FileSaveRequest`：`fileName`、`bytes` 必填；可选 `mimeType`、`dialogTitle`、`initialDirectory`。返回 `SavedFile?`，取消为 `null`；返回 `{uri,path,hasNativePath}`。它用于另存为压缩图片、下载内容或导出文件。

### `clearTemporaryFiles()`

无入参，返回 `bool`。清理系统选择器可清理的临时资源；调用后不可再依赖旧的 `fileId`。

## 图片与相机

`MediaPickRequest`：

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `allowMultiple` | boolean | false | 仅相册图片选择支持多选 |
| `preserveOriginal` | boolean | true | true 时不请求 picker 压缩；视频选择始终保留源视频 |
| `imageQuality` | int? | 85（仅非原图） | 0–100，交给 picker 压缩 |
| `maxWidth` / `maxHeight` | double? | null | 仅非原图时请求最大尺寸 |
| `maxDuration` | Duration? | null | 拍摄/选择视频最长时长，平台可限制或忽略 |

- `chooseImage(request)`：相册图片，返回 `List<SelectedFile>`。
- `takePhoto(request)`：相机拍照，返回 `SelectedFile?`。
- `compressImage(source, request)`：纯 Dart 处理，返回 `ProcessedImage`（`bytes`、`fileName`、`mimeType`、`width`、`height`、`originalSize`）；用 `saveFile` 保存。`ImageCompressionRequest` 为 `quality=85`、`maxWidth?`、`maxHeight?`、`format=jpeg|png|webp`。
- `decodeImageFile(source, formats)`：对已选择图片识别二维码；与图片选择解耦，返回 `ScanCodeResult?`。

## 视频

- `chooseVideo(request)`：相册选原视频，返回 `SelectedFile?`。
- `recordVideo(request)`：系统相机录像，返回 `SelectedFile?`。
- `getVideoMetadata(source)`：返回 `{durationMs,width,height,size,path}`。
- `createVideoThumbnail(source, quality=80, positionMs=0)`：返回 JPEG bytes。
- `compressVideo(source, quality=low|medium|high|original, includeAudio=true)`：返回新的 `SelectedFile?`，不删除原文件。

视频信息、缩略图、压缩目前由原生处理器承诺 Android、iOS、macOS；Windows/Linux/Web 或没有原始本机路径时明确抛出 `MediaCapabilityException`，调用方应保留原视频并提示用户。移动端优先支持，不以降低插件版本换取伪全平台能力。

## 录音

`AudioRecordingRequest`：`fileNamePrefix='gotoim_recording'`、`sampleRate=44100`、`bitRate=128000`、`numChannels=1`。输出为 AAC-LC/M4A。

| API | 返回 | 说明 |
| --- | --- | --- |
| `startAudioRecording(request)` | `Future<void>` | 请求麦克风权限并开始录制 |
| `pauseAudioRecording()` / `resumeAudioRecording()` | `Future<void>` | 暂停/继续当前会话 |
| `stopAudioRecording()` | `SelectedFile?` | 停止并保留录音，可立即上传 |
| `cancelAudioRecording()` | `Future<void>` | 停止并丢弃录音 |

Android 已声明 `RECORD_AUDIO`；iOS/macOS 已声明相机/相册/麦克风用途描述。首次使用仍必须接受系统授权。
