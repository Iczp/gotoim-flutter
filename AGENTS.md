# Flutter IM Project Development Rules

## 1. Project Goal

This project is a cross-platform IM client migrated from an existing UniApp Vue3 + TypeScript application.

Target platforms:

- Android
- iOS
- Android Tablet
- iPad
- Windows
- macOS
- Linux

The application communicates with an existing ABP vNext backend.

Backend technologies:

- .NET
- ABP vNext
- OpenIddict
- EF Core
- Redis
- SignalR
- MinIO

The Flutter application must preserve the existing IM business behavior and data synchronization semantics.

------

# 2. Core Architecture

The application uses the following architecture:

```text
UI
 ↓
Riverpod
 ↓
Repository
 ↓
 ┌──────────────┬──────────────┬──────────────┐
 │              │              │
Drift          Dio          SignalR
 │              │              │
 └──────────────┴──────────────┘
                ↓
             Backend
```

UI must NOT directly access:

- Dio
- Drift
- SignalR
- platform plugins
- SharedPreferences
- file system
- native APIs

UI communicates through Riverpod providers and repositories.

------

# 3. Main Technologies

Use:

- Flutter
- Dart
- Riverpod
- Dio
- go_router
- Drift
- SignalR client
- freezed
- json_serializable
- cached_network_image
- video_player
- permission_handler
- file_picker
- image_picker / wechat_assets_picker
- flutter_svg

Do not introduce another state-management framework unless explicitly requested.

Do not introduce GetX, Bloc, Provider, MobX, etc. without explicit approval.

------

# 4. Directory Structure

Preferred structure:

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   └── bootstrap.dart
│
├── core/
│   ├── network/
│   │   ├── api_client.dart
│   │   ├── api_result.dart
│   │   ├── api_exception.dart
│   │   ├── interceptors/
│   │   └── auth/
│   │
│   ├── database/
│   │   ├── app_database.dart
│   │   ├── tables/
│   │   └── dao/
│   │
│   ├── signalr/
│   │   ├── signalr_service.dart
│   │   └── handlers/
│   │
│   ├── jsbridge/
│   │   ├── js_bridge.dart
│   │   ├── js_api_dispatcher.dart
│   │   └── apis/
│   │
│   ├── platform/
│   │   ├── platform_facade.dart
│   │   ├── mobile/
│   │   ├── desktop/
│   │   ├── web/
│   │   └── stub/
│   │
│   └── utils/
│
├── data/
│   ├── models/
│   ├── repositories/
│   └── datasources/
│
├── services/
│   ├── window/
│   ├── notification/
│   ├── share/
│   ├── scan/
│   ├── file/
│   └── clipboard/
│
├── features/
│   ├── auth/
│   ├── session/
│   ├── chat/
│   ├── contact/
│   ├── user/
│   ├── media/
│   └── setting/
│
└── main.dart
```

Keep feature-specific code inside its feature directory.

Shared infrastructure belongs under `core`.

------

# 5. Repository Rules

Repositories are the boundary between business logic and data sources.

Example:

```text
MessageRepository
 ├── Drift
 ├── Dio
 └── SignalR
```

Repositories may use:

- local database
- HTTP
- SignalR
- cache

UI must not.

For example:

Correct:

```text
ChatPage
 ↓
MessageProvider
 ↓
MessageRepository
 ↓
Drift
```

Incorrect:

```text
ChatPage
 ↓
Dio.get()
```

------

# 6. Dio / HTTP Rules

Use one shared Dio client.

Do not create Dio instances in feature pages.

Required capabilities:

- Base URL
- Access Token
- Refresh Token
- 401 handling
- concurrent refresh protection
- API error handling
- request cancellation
- multipart upload
- file download
- upload progress
- download progress
- request logging in development

ABP vNext response format must be supported.

Typical response:

```json
{
  "result": {},
  "success": true,
  "error": null,
  "targetUrl": null,
  "unAuthorizedRequest": false
}
```

401 refresh behavior:

```text
Request
 ↓
401
 ↓
Refresh Token
 ↓
success
 ↓
retry original request
```

If multiple requests receive 401 simultaneously:

- only ONE refresh request may be active
- other requests must wait
- after refresh succeeds, retry waiting requests
- after refresh fails, logout

Never start multiple concurrent refresh-token requests.

------

# 7. Token Rules

AccessToken and RefreshToken must be stored through a dedicated TokenStorage.

Do not directly access storage from UI.

Required:

```text
TokenStorage
 ├── accessToken
 ├── refreshToken
 ├── save()
 ├── clear()
 └── hasToken()
```

SignalR must obtain the latest access token through the same token provider.

------

# 8. Drift / SQLite Rules

Drift is the primary local data store.

SQLite is not just a temporary cache.

For IM data, SQLite is the local source of truth for the currently synchronized data.

Recommended tables:

```text
Messages
Sessions
SessionUnits
Users
Attachments
```

Use DAO classes.

Business code should not directly execute Drift queries.

------

# 9. Message Table Rules

Messages must distinguish between:

```text
localId
serverId
clientMessageId
sessionId
sessionMessageId
```

Recommended semantics:

```text
localId
    Local SQLite primary key.

serverId
    Server-generated message ID.
    May be null for unsent local messages.

clientMessageId
    Client-generated unique ID.
    Used for deduplication and send-result matching.

sessionId
    Chat session ID.

sessionMessageId
    Session-scoped message sequence.
```

Do not use serverId as the only local primary key.

Local pending messages must be supported.

------

# 10. Message Status

Messages should support states similar to:

```text
Pending
Sending
Sent
Failed
Delivered
Read
Recalled
Deleted
```

The exact enum names may differ, but the state model must distinguish local sending state from server message state.

Do not delete failed messages automatically.

------

# 11. Message Synchronization

The synchronization model is:

```text
HTTP
 ↓
Drift
 ↓
Riverpod
 ↓
UI
```

SignalR is a real-time event transport.

SignalR is NOT the authoritative offline message store.

When receiving a SignalR message:

```text
SignalR
 ↓
MessageRepository
 ↓
Upsert Drift
 ↓
Riverpod stream
 ↓
UI
```

Never directly mutate UI state from SignalR.

------

# 12. SignalR Rules

Use one application-level SignalR connection where possible.

Do not create one SignalR connection per chat page.

Responsibilities:

- connect
- disconnect
- reconnect
- connection state
- event registration
- invoke
- event dispatch

Typical events:

```text
ReceiveMessage
ReceiveRecall
ReceiveDelete
ReceiveRead
ReceiveTyping
ReceiveOnline
ReceiveOffline
ReceiveSessionUpdate
ReceiveBadgeUpdate
```

SignalR reconnection must be automatic.

After reconnection, perform HTTP incremental synchronization when necessary.

Do not assume SignalR guarantees delivery while disconnected.

------

# 13. Message Sending

Preferred flow:

```text
UI
 ↓
create clientMessageId
 ↓
insert local pending message
 ↓
UI immediately displays message
 ↓
HTTP send
 ↓
server response
 ↓
update local message
 ↓
SignalR events synchronize other clients
```

Do not make SignalR the only mechanism for sending business messages.

------

# 14. Read Receipt

The application already uses:

```text
ReadMessageId
PeerReadMessageId
```

Do not replace these with a per-message read record unless explicitly required.

For a one-to-one conversation:

```text
ReadMessageId
    Local user's read position

PeerReadMessageId
    Other user's read position
```

Use these values to determine whether a message is read.

------

# 15. Chat List

Do not translate the old UniApp virtual-list implementation directly.

Flutter must use Flutter's rendering model.

Preferred:

```text
CustomScrollView
 ↓
SliverList
```

Message item heights are variable.

The list must support:

- text messages
- image messages
- video messages
- file messages
- voice messages
- system messages
- recalled messages
- deleted messages
- time dividers
- "new messages" divider

Do NOT assume a fixed item height.

Do NOT manually implement DOM-style:

```text
height
offset
translateY
visibleItems
```

unless a specific performance issue proves it necessary.

------

# 16. ChatItem

The UI list should use a presentation model such as:

```text
ChatItem
 ├── TimeDivider
 ├── MessageItem
 ├── NewMessageDivider
 ├── SystemMessage
 └── OtherSpecialItem
```

Different ChatItems may have completely different heights.

Example:

```text
TimeDivider
Message
Message
ImageMessage
NewMessageDivider
Message
SystemMessage
```

Flutter is responsible for measuring widget heights.

------

# 17. Chat Pagination

Do not load hundreds of thousands of messages into memory.

Use incremental loading.

Typical flow:

```text
SQLite
 ↓
load latest N
 ↓
display
 ↓
user scrolls upward
 ↓
load older messages
 ↓
SQLite
 ↓
if insufficient
 ↓
HTTP
 ↓
upsert SQLite
 ↓
display
```

When loading history, preserve the user's current scroll position.

Do not cause the chat to jump after prepending older messages.

------

# 18. Session List

Session list should be backed by local SQLite data.

Typical:

```text
SignalR / HTTP
 ↓
SessionRepository
 ↓
Drift
 ↓
Riverpod
 ↓
SessionList
```

Unread count, last message, sorting and related session state should be persisted locally.

------

# 19. Media

Messages may contain:

- image
- video
- audio
- file

Use an Attachment model/table.

Recommended fields include:

```text
id
messageId
type
url
localPath
fileName
size
mimeType
downloadState
uploadState
```

Do not store large binary files directly inside SQLite.

Actual private files should be stored in the application file system / MinIO.

------

# 20. MinIO

MinIO files are private.

The Flutter client should not assume that object URLs are public.

Use the backend to obtain authorized access or temporary signed URLs.

Do not expose permanent private MinIO credentials to the client.

------

# 21. WebView / H5

The H5 application is built with UniApp.

The Flutter application must provide a JSBridge compatible with the existing H5 JS API whenever possible.

Architecture:

```text
UniApp H5
 ↓
goto.xxx()
 ↓
JavaScriptChannel
 ↓
JsBridge
 ↓
JsApiDispatcher
 ↓
PlatformFacade / Service
 ↓
Native API
```

The H5 layer should not need to know whether the host is Flutter, Android or iOS.

------

# 22. JSBridge Protocol

Use a request/response protocol.

Request:

```json
{
  "id": "unique-request-id",
  "action": "chooseImage",
  "data": {}
}
```

Response:

```json
{
  "id": "unique-request-id",
  "success": true,
  "data": {}
}
```

Error:

```json
{
  "id": "unique-request-id",
  "success": false,
  "error": {
    "code": "USER_CANCEL",
    "message": "User cancelled"
  }
}
```

All asynchronous APIs should return Promises on the H5 side.

Example:

```javascript
const result = await goto.chooseImage();
```

------

# 23. JSAPI Compatibility

Before implementing JSAPI, scan the existing UniApp project and identify the actual APIs currently used.

Do not invent APIs without checking the existing project.

Potential APIs include:

```text
login
logout
chooseImage
chooseVideo
chooseFile
scanCode
previewImage
getLocation
openLocation
setClipboardData
getClipboardData
share
showToast
showLoading
hideLoading
navigateTo
close
openSession
openUser
```

Only implement APIs that are actually required.

------

# 24. Platform Architecture

Business code must not directly depend on platform-specific APIs.

Avoid:

```dart
if (Platform.isWindows)
```

inside business features.

Instead use:

```text
PlatformFacade
 ↓
Platform-specific Service
```

Examples:

```text
WindowService
NotificationService
ShareService
ScanService
ClipboardService
FilePickerService
```

------

# 25. Conditional Imports

Use Dart conditional imports when a source file imports platform-specific libraries.

Examples:

```text
platform_service.dart
platform_service_mobile.dart
platform_service_desktop.dart
platform_service_web.dart
platform_service_stub.dart
```

Do not import:

```text
dart:html
```

or platform-specific APIs from shared business code.

------

# 26. Desktop Windows

Desktop platforms support:

- Windows
- macOS
- Linux

Desktop-specific features include:

```text
multiple windows
system tray
desktop notifications
window resizing
always-on-top
minimize/maximize
```

These must be implemented behind services.

Business code must not directly depend on:

```text
desktop_multi_window
window_manager
tray_manager
```

------

# 27. Multiple Desktop Windows

Main window:

```text
Session List
```

Chat window:

```text
Chat
```

Opening a chat:

```text
WindowService.openChat(sessionId)
```

Do not call desktop_multi_window directly from Chat UI.

Window manager should maintain:

```text
sessionId -> windowId
```

If the session is already open:

```text
activate existing window
```

Otherwise:

```text
create new window
```

All windows should share the same data model and synchronization architecture.

------

# 28. Mobile Window Behavior

On mobile:

```text
WindowService.openChat(sessionId)
```

should navigate within the current application instead of creating a desktop window.

The business API must remain the same.

Example:

```text
Desktop:
openChat()
 ↓
new window

Mobile:
openChat()
 ↓
Navigator/go_router
```

------

# 29. Responsive UI

The application must support:

```text
Phone
Tablet
Desktop
```

Use:

```text
LayoutBuilder
MediaQuery
breakpoints
```

Do not simply scale the mobile UI.

Typical layout:

```text
Phone:
Chat

Tablet:
SessionList | Chat

Desktop:
Navigation | SessionList | Chat
```

The exact breakpoints should be defined centrally.

------

# 30. Pixel / rpx Migration

The existing UniApp project uses rpx.

Flutter uses logical pixels.

If preserving the existing 750-width design system is useful, use a centralized adapter such as ScreenUtil or an rpx extension.

Do not scatter custom rpx conversion logic throughout the application.

Preferred example:

```dart
28.rpx
```

or a centralized responsive sizing utility.

------

# 31. Routing

Use go_router.

Routing should support:

- login
- main
- session
- chat
- user
- settings
- deep links

Authentication redirect logic should be centralized.

Do not manually perform route authentication checks in every page.

------

# 32. State Management

Use Riverpod.

Prefer:

```text
Provider
NotifierProvider
AsyncNotifierProvider
StreamProvider
```

depending on the use case.

For database streams:

```text
Drift Stream
 ↓
Riverpod StreamProvider
 ↓
UI
```

Avoid unnecessary manual event buses.

------

# 33. Error Handling

Create application-level exceptions.

Examples:

```text
ApiException
AuthException
NetworkException
DatabaseException
PlatformException
JsApiException
```

Do not expose raw Dio / SQLite / platform exceptions directly to UI.

Convert infrastructure exceptions at the appropriate boundary.

------

# 34. Logging

Use a centralized logger.

Development:

- request
- response
- SignalR connection
- database synchronization
- JSBridge
- platform services

Production:

- do not log tokens
- do not log passwords
- do not log private message content unnecessarily
- do not log private file URLs unnecessarily

------

# 35. Security

Never expose:

- OpenIddict client secrets intended for server-side use
- MinIO permanent access keys
- Refresh tokens in logs
- private encryption keys

Do not hardcode production secrets.

------

# 36. Testing

Every major infrastructure component should have tests.

At minimum:

```text
ApiClient
Token refresh
MessageRepository
MessageDao
SessionDao
SignalR event handling
JSBridge dispatch
Platform service
```

Important test:

Multiple simultaneous HTTP requests receive 401.

Expected:

```text
1 refresh request
N waiting requests
N requests retry after refresh
```

------

# 37. Code Generation

Use code generation where appropriate:

```text
freezed
json_serializable
drift
```

After modifying generated models or Drift tables, run the appropriate build_runner command.

Do not manually edit generated files.

------

# 38. Migration Strategy

Do not migrate the whole UniApp application in one step.

Recommended order:

```text
1. Flutter project
2. Architecture
3. Platform abstraction
4. Dio
5. Token / authentication
6. Drift
7. Message DAO
8. Session DAO
9. Repository
10. SignalR
11. JSBridge
12. Login
13. Main / Session List
14. Contact
15. Chat
16. Media
17. Desktop features
18. Tablet optimization
19. H5 integration
20. Testing / performance
```

------

# 39. Important Migration Rule

Do NOT blindly translate Vue/UniApp code to Dart.

For example:

UniApp:

```text
virtual-list
```

must not become a custom Flutter virtual-list simply because the original code used one.

Instead use Flutter-native solutions:

```text
CustomScrollView
SliverList
```

Similarly:

```text
Pinia
```

should become Riverpod architecture rather than a direct syntax translation.

------

# 40. Existing Backend Compatibility

Do not modify backend APIs unless explicitly requested.

Existing ABP backend contracts should be treated as external contracts.

Before changing a DTO/model:

1. inspect existing UniApp API implementation
2. inspect backend DTO
3. inspect actual JSON response
4. implement Flutter model
5. add serialization test

------

# 41. Development Workflow

For every task:

```text
1. Inspect existing code
2. Identify related architecture
3. Make the smallest change
4. Run formatter
5. Run flutter analyze
6. Run relevant tests
7. Fix errors
8. Summarize changes
```

Do not perform unrelated refactoring while implementing a feature.

------

# 42. Before Writing Code

For non-trivial tasks:

First explain briefly:

```text
- files to change
- architecture impact
- implementation approach
- potential risks
```

Then implement.

Do not ask for confirmation for ordinary implementation tasks unless the requested change is ambiguous or destructive.

------

# 43. Do Not Create Duplicate Infrastructure

Before creating a new:

- API client
- Repository
- Service
- Database
- SignalR connection
- JSBridge
- Platform abstraction

search the project first.

Reuse existing infrastructure.

Do not create:

```text
ApiClient2
MessageRepositoryNew
SignalRManager2
```

just because the existing implementation is inconvenient.

------

# 44. Performance

This is an IM application.

Pay special attention to:

- message list rebuilds
- database queries
- image decoding
- video memory
- unnecessary Riverpod rebuilds
- SignalR event frequency
- large group sessions
- large message histories

Do not rebuild the entire chat list when a single message changes.

Use appropriate provider granularity.

------

# 45. Chat Performance

Avoid:

```text
setState()
 ↓
rebuild entire 1000-message list
```

Prefer:

```text
message provider
 ↓
fine-grained update
```

Images and videos must be lazy loaded.

Do not preload all media.

------

# 46. Offline First

The application should work with the local database whenever possible.

Typical flow:

```text
UI
 ↓
Drift
 ↓
immediate data

Network
 ↓
sync
 ↓
Drift
 ↓
UI updates
```

Do not make every screen wait for HTTP before displaying existing local data.

------

# 47. Final Architectural Principle

The most important rule:

```text
UI does not know where data comes from.

Repository does not know which platform the UI is running on.

Business code does not know whether it is Android,
iOS, Tablet, Windows, macOS or Linux.

Platform services hide platform differences.

Drift is the local data source.

Dio is the HTTP transport.

SignalR is the realtime transport.

Riverpod is the application state layer.

JSBridge is the H5/native boundary.
```

The final architecture should remain:

```text
                   Flutter App
                       │
                    Riverpod
                       │
                  Repositories
                       │
        ┌──────────────┼──────────────┐
        │              │              │
      Drift           Dio          SignalR
        │              │              │
        └──────────────┼──────────────┘
                       │
                    Backend


                PlatformFacade
                       │
        ┌──────────────┼──────────────┐
        │              │              │
      Mobile         Desktop         Web
        │              │              │
   Native APIs     Window/Tray     Browser APIs


                    WebView
                       │
                    JSBridge
                       │
                JsApiDispatcher
                       │
                 PlatformFacade
```

## Codex 执行原则

When implementing a task, always follow this document.

If existing code conflicts with these rules:

1. Preserve existing business behavior.
2. Do not silently change backend contracts.
3. Prefer the architecture defined here.
4. Report architectural conflicts before making a large refactor.
5. Keep changes focused and incremental.