# Flutter Social 接入

“我的 → 常用服务 → Social 社交”进入 `/social`，支持推荐/关注动态、游标分页、文字发布和通知收件箱。

## 身份与切换

Social 身份按主应用当前 ChatObject 绑定，ActorKey 为 `chat:{ChatObjectId}`。进入社区、通知或发布页时先验证当前 ChatObject 的归属；尚未创建时弹出确认，点击“确认创建”才创建。启动、通知轮询和查看别人的资料卡均不会自动创建身份。

主应用切换身份后，社区随之切换，清除旧动态、未读数和发布草稿。旧请求的迟到结果被忽略；旧身份的创建确认框关闭，避免误建。不同 ChatObject 可以对应不同 Actor，不能使用账号默认 Actor 替代。

## 独立客户端

`socialDioProvider` 与 `socialApiClientProvider` 为 Social 专用实例，不与 Chat 共用客户端。配置 `SOCIAL_API_BASE_URL` 为服务或网关根地址，不追加 `/api/social`；为空时地址回退到 API_BASE_URL，实例仍独立。统一复用认证存储和刷新协调，用户令牌需要 Chat 与 Social 范围；旧授权需重新登录。

## 资料卡

手机半屏卡、完整资料页、桌面弹窗和原生悬浮资料卡显示目标 ChatObject 最近三条可见动态，以及关注数、粉丝数、当前查看身份是否关注目标。少于三条显示实际数量；身份未创建、无动态和请求失败有独立提示。不按昵称猜测，也不回退到自己的动态。

好友使用 destination，成员使用 owner，自己的身份使用自身 ChatObject ID。读取 `/api/social/actor/for-chat-object?chatObjectId={chatObjectId}`，携带当前查看者 ViewerActorId；随后读取 actor-posts，PageSize=3。查看者没有 Social 身份时使用 PublicOnly，不回退到账户默认身份的权限。点击动态重新校验详情可见性。关注信息目前只展示，不包含关注/取消关注操作。

原生桌面浮窗通过主窗口 IPC 读取预览和详情，身份切换时刷新；不复制令牌或创建第二个认证客户端。开发诊断 `/diagnostics/social-profile` 可输入 ChatObject ID，查询并复制无令牌结果。

## 提醒与发布

只有当前已创建身份才启动通知读取。前台每 30 秒轮询，后台暂停，恢复时立即检查；首次历史未读只更新角标，后续增加时显示应用内提醒，尊重全局通知开关。收件箱支持单条/全部已读及游标加载。这不是应用退出后的系统推送。

发布支持 1–2000 字及公开、关注者、仅自己可见；相同内容重试复用 ClientRequestId，防止重复提交。服务端成功后才反馈成功并刷新预览。媒体上传、主动点赞和回复尚未接入。

## 验证

`flutter test --no-pub test/social_chat_identity_test.dart test/profile_social_preview_test.dart test/social_notifications_publish_test.dart test/social_integration_test.dart test/app_environment_test.dart`：32 项通过。覆盖创建确认、切换时旧请求/确认失效、最新三条、关注信息、原生浮窗刷新、独立客户端、通知和发布。

后端相关测试 10 项通过，覆盖 Chat 归属校验、身份转移、重复创建、查看者关注状态、只读公开预览及 HTTP 元数据请求。无数据库结构变更，无 Migration；不访问开发数据库。未使用真实用户发布测试内容；其他平台及真实账号多身份操作仍需实机验收。


Social API 发布清单：Rctea.IM/deploy/releases/social-chat-identity-20261026-1/manifest.json，Applied/Passed。线上只读接口匿名及 IM audience 返回 401，Social audience 查询未知 ChatObject 返回 204；机器令牌 resolve 返回 403。实际路由的 chatObjectId 为查询参数。
