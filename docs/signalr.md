# SignalR gateway

## Configuration

SignalR configuration lives in the root environment files:

| Key | Meaning |
| --- | --- |
| `SIGNALR_BASE_URL` | Chat realtime host |
| `SIGNALR_HUB_PATH` | Current UniApp chat hub: `/signalr-hubs/chat` |
| `SIGNALR_SKIP_NEGOTIATION` | Set `true` only when the server supports direct WebSocket transport |
| `SIGNALR_RECONNECT_DELAYS_MS` | Comma-separated retry delays, e.g. `0,2000,10000,30000` |

`SignalRNetcoreGateway` uses `HttpTransportType.WebSockets`, registers one
application-level `ReceivedMessage` handler, and reads the current access token
from `TokenStorage` through `accessTokenFactory`. It is not created per chat
page.

## Event model

The current UniApp app receives a `ReceivedMessage` envelope and dispatches its
`command`. The Flutter gateway preserves these values as typed commands:

| SignalR `command` | Flutter enum |
| --- | --- |
| `offline@me` / `online@me` | `offlineMe` / `onlineMe` |
| `offline@friend` / `online@friend` | `offlineFriend` / `onlineFriend` |
| `created@message` | `messageCreated` |
| `forwarded@message` | `messageForwarded` |
| `updated@message` | `messageUpdated` |
| `updated-badge@message` | `messageBadgeUpdated` |
| `rollbacked@message` | `messageRollbacked` |
| `changed@session-unit` | `sessionUnitChanged` |
| `kicked` / `welcome` | `kicked` / `welcome` |

Unknown or malformed envelopes become `SignalRUnknownCommandEvent`; they are
not silently discarded. Connection changes produce `SignalRConnectionEvent`
with `connecting`, `connected`, `reconnecting`, `disconnecting`, or
`disconnected`.

## Repository usage

The composition root supplies `signalRGatewayProvider`; it deliberately does
not connect before authentication succeeds. `AuthController` starts it after a
successful login or restored session and stops it at logout. Repositories, not
UI, subscribe to command streams:

```dart
gateway.events.forCommand(SignalRCommand.messageCreated).listen((event) async {
  // validate DTO -> upsert Drift -> Riverpod watches the database
});
```

On `connected` after a reconnect, a repository must run HTTP incremental sync.
SignalR is a low-latency notification path, not the offline source of truth.
Do not update a screen directly from this stream.

## Initial failures and retry

Automatic reconnect applies after a connection has been established. The auth
or application lifecycle should decide how to retry an **initial** `connect()`
failure (typically using a bounded, observable backoff); it should not block a
login screen indefinitely. This follows the SignalR client reconnect model
described in [Microsoft's SignalR client documentation](https://learn.microsoft.com/en-us/aspnet/core/signalr/javascript-client?view=aspnetcore-10.0).

## Platform note

The current project is pinned to `signalr_netcore` 1.3.6 to remain compatible
with its installed Dart 2.19 SDK. The IO implementation therefore covers
Android, iOS, Windows, macOS, and Linux. The Web conditional implementation is
an explicit unsupported stub until the Flutter SDK and a web-compatible SignalR
client have been upgraded and verified; shared business code remains platform
independent.
