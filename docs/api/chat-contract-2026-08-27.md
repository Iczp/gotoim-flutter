# Chat API contract snapshot

Captured from `http://10.0.5.20:8044` on 2026-08-27.

Raw sources:

- `swagger-v1-2026-08-27.json`
- `abp-api-definition-2026-08-27.json`

The raw files are the source of truth. This index records the endpoints used by
the Flutter chat implementation.

| Capability | Method and path | Parameters/body |
| --- | --- | --- |
| Set read position | `POST /api/chat/session-unit-setting/set-read` | Query: required `sessionUnitId` UUID; optional `messageId` int64 and `isForce` bool. Returns `SessionUnitOwnerDto`. |
| Delete message for current session unit | `POST /api/chat/session-unit-setting/delete-message` | Query: required `sessionUnitId` UUID; optional `messageId` int64. |
| Recall message | `POST /api/chat/message-sender/rollback/{messageId}` | Path: required `messageId` int64. Returns a string/int64 map. |
| Forward message | `POST /api/chat/message-sender/forward` | Query: `sessionUnitId` UUID and `messageId` int64. JSON body: target session-unit UUID array. Returns `MessageDto[]`. |
| Forward selected messages as one history card | `POST /api/chat/message-sender/send-history/{sessionUnitId}` | JSON body: `clientMessageId`, `content.messageIdList` (int64 array). |
| Upload image | `POST /api/chat/message-sender/send-upload-image/{sessionUnitId}` | Multipart `file`; query supports `quoteMessageId`, `remindList`, `isOriginal`. |
| Upload video | `POST /api/chat/message-sender/send-upload-video/{sessionUnitId}` | Multipart `file`; query supports `quoteMessageId`, `remindList`, `isOriginal`. |
| Upload generic attachment | `POST /api/chat/message-sender/send-upload-file/{sessionUnitId}` | Multipart `file`; query supports `quoteMessageId` and `remindList`. |
| Force all readers read | `POST /api/chat/readed-recorder/set-all/{messageId}` | Administrative/group operation; not used to submit the current user's normal read position. |

`set-readed-message-id` exists but is deprecated. New code uses `set-read`.
